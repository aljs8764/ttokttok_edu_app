import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/flavor.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../teacher/models.dart' show Attendance;

/// 학생앱 API (스펙 7-7). 학생은 계정이 없어 JWT 대신 X-Device-Token 으로 인증한다.
/// 토큰은 보호자가 만든 8자리 연결 코드로 한 번 받고 secure storage 에 둔다.

/// 기기는 아이에 묶인다 (스펙 7-8) — 아이가 다니는 모든 기관에서 이 폰으로 출석
class StudentInfo {
  const StudentInfo({required this.childId, required this.studentName, required this.institutionNames});

  final String childId;
  final String studentName;
  final List<String> institutionNames;

  String get institutionName => institutionNames.isEmpty ? '' : institutionNames.join(' · ');

  factory StudentInfo.fromJson(Map<String, dynamic> d) => StudentInfo(
        childId: (d['child'] as Map)['id'] as String,
        studentName: (d['child'] as Map)['name'] as String,
        institutionNames: (d['institutions'] as List? ?? const []).map((i) => (i as Map)['name'] as String).toList(),
      );
}

class TodayClass {
  const TodayClass({
    required this.institutionName,
    required this.classroomId,
    required this.classroomName,
    required this.startTime,
    required this.endTime,
    this.attendance,
  });

  final String institutionName;
  final String classroomId;
  final String classroomName;
  final String startTime;
  final String endTime;
  final Attendance? attendance;

  factory TodayClass.fromJson(Map<String, dynamic> j) => TodayClass(
        institutionName: j['institutionName'] as String? ?? '',
        classroomId: j['classroomId'] as String,
        classroomName: j['classroomName'] as String,
        startTime: (j['startTime'] as String).substring(0, 5),
        endTime: (j['endTime'] as String).substring(0, 5),
        attendance: j['attendance'] == null ? null : Attendance.fromJson(j['attendance'] as Map<String, dynamic>),
      );
}

class StudentHome {
  const StudentHome({required this.info, required this.today});

  final StudentInfo info;
  final List<TodayClass> today;
}

class DestinationOption {
  const DestinationOption({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final String type;
}

/// POST /student/scan 결과
enum ScanOutcome { checkedIn, checkedOut, chooseDestination, alreadyDone }

class ScanResult {
  const ScanResult({required this.outcome, this.classroomName, this.institutionName, this.attendance, this.destinations = const []});

  final ScanOutcome outcome;
  final String? classroomName;
  final String? institutionName;
  final Attendance? attendance;
  final List<DestinationOption> destinations;

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        outcome: switch (j['outcome']) {
          'CHECKED_IN' => ScanOutcome.checkedIn,
          'CHECKED_OUT' => ScanOutcome.checkedOut,
          'CHOOSE_DESTINATION' => ScanOutcome.chooseDestination,
          _ => ScanOutcome.alreadyDone,
        },
        classroomName: j['classroomName'] as String?,
        institutionName: j['institutionName'] as String?,
        attendance: j['attendance'] == null ? null : Attendance.fromJson(j['attendance'] as Map<String, dynamic>),
        destinations: (j['destinations'] as List? ?? const [])
            .map((d) => DestinationOption(id: d['id'] as String, name: d['name'] as String, type: d['type'] as String))
            .toList(),
      );
}

class StudentApi {
  StudentApi(this._storage)
      : _dio = Dio(BaseOptions(
          baseUrl: '${Env.apiBaseUrl}/api/v1/student/',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
        ));

  final Dio _dio;
  final FlutterSecureStorage _storage;
  String? _token;

  static const _key = 'student_device_token';

  Future<bool> restore() async {
    _token = await _storage.read(key: _key);
    return _token != null;
  }

  bool get linked => _token != null;

  Options get _auth => Options(headers: {'X-Device-Token': _token});

  /// STD-001 연결 코드 → 기기 토큰
  Future<StudentInfo> link(String code, String deviceName) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('link', data: {'code': code, 'deviceName': deviceName});
        final d = r.data!;
        _token = d['deviceToken'] as String;
        await _storage.write(key: _key, value: _token);
        return StudentInfo.fromJson(d);
      });

  Future<StudentHome> me() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('me', options: _auth);
        final d = r.data!;
        return StudentHome(
          info: StudentInfo.fromJson(d),
          today: (d['today'] as List).map((c) => TodayClass.fromJson(c as Map<String, dynamic>)).toList(),
        );
      });

  /// 같은 스캔을 다시 보낼 땐 같은 키 (네트워크 재시도). 목적지를 골라 다시 보낼 땐 새 키.
  Future<ScanResult> scan({
    required String qr,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? destinationId,
    required String idempotencyKey,
  }) =>
      _call(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          'scan',
          data: {
            'qr': qr,
            'latitude': latitude,
            'longitude': longitude,
            'accuracy': accuracy,
            'destinationId': destinationId,
            'clientAt': DateTime.now().toUtc().toIso8601String(),
          },
          options: Options(headers: {'X-Device-Token': _token, 'Idempotency-Key': idempotencyKey}),
        );
        return ScanResult.fromJson(r.data!);
      });

  Future<void> logout() async {
    try {
      if (_token != null) await _dio.post<void>('logout', options: _auth);
    } catch (_) {
      // 오프라인이어도 이 기기에서는 지운다
    }
    await forget();
  }

  Future<void> forget() async {
    _token = null;
    await _storage.delete(key: _key);
  }

  static String newKey() => ApiClient.newIdempotencyKey();

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      final err = ApiException.from(e);
      // 보호자가 연결을 해제했거나 다른 기기로 바뀜 → 다시 연결
      if (err.status == 401) await forget();
      throw err;
    }
  }
}

final studentApiProvider = Provider<StudentApi>(
  (ref) => StudentApi(const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))),
);

/// 연결 여부 (라우터 redirect 가 본다)
class StudentLinkState extends Notifier<bool> {
  @override
  bool build() => ref.read(studentApiProvider).linked;

  void set(bool linked) => state = linked;
}

final studentLinkedProvider = NotifierProvider<StudentLinkState, bool>(StudentLinkState.new);

final studentHomeProvider = FutureProvider.autoDispose<StudentHome>((ref) async {
  try {
    return await ref.watch(studentApiProvider).me();
  } on ApiException catch (e) {
    if (e.status == 401) ref.read(studentLinkedProvider.notifier).set(false);
    rethrow;
  }
});
