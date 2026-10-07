import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'models.dart';
import 'teacher_providers.dart';
import 'teacher_repository.dart';

/// 네트워크가 없을 때 누른 등원·하원 한 건 (ATT-005·006 오프라인 큐, 스펙 6장).
/// 같은 Idempotency-Key·clientAt 으로 POST /attendance/bulk 에 실어 보내므로, 응답만 놓친 요청이 이미 처리됐어도 중복되지 않는다.
class QueuedAttendance {
  const QueuedAttendance({
    required this.key,
    required this.type,
    required this.studentId,
    required this.studentName,
    required this.classroomId,
    required this.clientAt,
    required this.userId,
    required this.institutionId,
    this.destinationId,
    this.destinationName,
  });

  /// 'CHECK_IN' | 'CHECK_OUT'
  final String type;
  final String key;
  final String studentId;
  final String studentName;
  final String classroomId;
  final String? destinationId;
  final String? destinationName;
  final DateTime clientAt;

  /// 누른 사람·기관 — 다른 계정·기관으로 바뀐 뒤에는 보내지 않는다
  final String userId;
  final String institutionId;

  bool get isCheckIn => type == 'CHECK_IN';
  String get label => isCheckIn ? '등원' : '하원';

  factory QueuedAttendance.fromJson(Map<String, dynamic> j) => QueuedAttendance(
        key: j['key'] as String,
        type: j['type'] as String,
        studentId: j['studentId'] as String,
        studentName: j['studentName'] as String,
        classroomId: j['classroomId'] as String,
        destinationId: j['destinationId'] as String?,
        destinationName: j['destinationName'] as String?,
        clientAt: DateTime.parse(j['clientAt'] as String),
        userId: j['userId'] as String,
        institutionId: j['institutionId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'studentId': studentId,
        'studentName': studentName,
        'classroomId': classroomId,
        'destinationId': destinationId,
        'destinationName': destinationName,
        'clientAt': clientAt.toUtc().toIso8601String(),
        'userId': userId,
        'institutionId': institutionId,
      };

  /// POST /attendance/bulk 항목
  Map<String, dynamic> toBulkJson() => {
        'type': type,
        'studentId': studentId,
        'classroomId': classroomId,
        'destinationId': destinationId,
        'clientAt': clientAt.toUtc().toIso8601String(),
        'idempotencyKey': key,
      };
}

/// bulk 응답 한 항목 (index = 요청 순서)
class BulkResult {
  const BulkResult({required this.index, required this.ok, this.errorCode, this.message});

  final int index;
  final bool ok;
  final String? errorCode;
  final String? message;

  factory BulkResult.fromJson(Map<String, dynamic> j) => BulkResult(
        index: (j['index'] as num).toInt(),
        ok: j['ok'] as bool,
        errorCode: j['errorCode'] as String?,
        message: j['message'] as String?,
      );
}

/// 전송에 실패해 버린 항목 안내 (화면이 한 번 보여 주고 비운다)
final queueFailuresProvider = StateProvider<List<String>>((ref) => const []);

/// 오프라인 큐. 기기 저장소(shared_preferences)에 남겨 앱을 껐다 켜도 유지한다.
/// 15초마다·앱 복귀 시·다른 요청이 성공했을 때 보내 보고, 네트워크 오류면 그대로 둔다.
class AttendanceQueueController extends Notifier<List<QueuedAttendance>> {
  static const _prefKey = 'attendance_queue';
  static const _chunk = 100;

  Timer? _timer;
  Future<void>? _loading;
  bool _flushing = false;

  @override
  List<QueuedAttendance> build() {
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  /// 앱 시작(교사앱 홈)에서 한 번 — 저장된 큐를 읽고 바로 보내 본다
  Future<void> start() async {
    await _ensureLoaded();
    unawaited(flush());
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getStringList(_prefKey) ?? const [];
    final saved = <QueuedAttendance>[];
    for (final s in raw) {
      try {
        saved.add(QueuedAttendance.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // 깨진 항목은 버린다
      }
    }
    // 불러오는 사이 쌓인 것은 뒤에 붙인다
    state = [...saved, ...state];
    _syncTimer();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, [for (final q in state) jsonEncode(q.toJson())]);
  }

  void _syncTimer() {
    if (state.isEmpty) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => flush());
    }
  }

  bool hasFor(String studentId) => state.any((q) => q.studentId == studentId);

  List<QueuedAttendance> forClass(String classroomId) => state.where((q) => q.classroomId == classroomId).toList();

  Future<void> enqueue(QueuedAttendance item) async {
    await _ensureLoaded();
    state = [...state, item];
    _syncTimer();
    await _save();
  }

  /// 쌓인 것을 보낸다. 반환: 서버가 받아 간 건수. 동시에 두 번 돌지 않는다.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      await _ensureLoaded();
      final auth = ref.read(authControllerProvider);
      final mine = state.where((q) => q.userId == auth.user?.id && q.institutionId == auth.institutionId).toList();
      final failures = <String>[];
      for (var i = 0; i < mine.length; i += _chunk) {
        final chunk = mine.sublist(i, i + _chunk > mine.length ? mine.length : i + _chunk);
        final List<BulkResult> results;
        try {
          results = await ref.read(teacherRepositoryProvider).bulk(chunk);
        } catch (e) {
          final err = ApiException.from(e);
          final status = err.status;
          // 네트워크·서버 오류·인증 갱신 중이면 그대로 두고 다음에 다시. 요청 자체가 거절(4xx)되면 버린다
          final permanent = status != null && status >= 400 && status < 500 && status != 401 && status != 408 && status != 429;
          if (!permanent) break;
          for (final q in chunk) {
            failures.add('${q.studentName} ${q.label}: ${err.message}');
          }
          _remove(chunk.map((q) => q.key).toSet());
          continue;
        }
        final done = <String>{};
        for (final r in results) {
          if (r.index < 0 || r.index >= chunk.length) continue;
          final q = chunk[r.index];
          done.add(q.key);
          if (r.ok) {
            sent++;
          } else {
            failures.add('${q.studentName} ${q.label}: ${r.message ?? r.errorCode ?? '처리하지 못했습니다'}');
          }
        }
        _remove(done);
      }
      await _save();
      _syncTimer();
      if (sent > 0 || failures.isNotEmpty) {
        // 서버 기준으로 반 출결을 다시 읽는다 (대기 표시 해제·실패 항목 되돌림)
        ref.invalidate(classAttendanceProvider);
      }
      if (failures.isNotEmpty) ref.read(queueFailuresProvider.notifier).state = failures;
    } finally {
      _flushing = false;
    }
    return sent;
  }

  void _remove(Set<String> keys) => state = state.where((q) => !keys.contains(q.key)).toList();
}

final attendanceQueueProvider = NotifierProvider<AttendanceQueueController, List<QueuedAttendance>>(AttendanceQueueController.new);
