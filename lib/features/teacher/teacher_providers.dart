import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'attendance_queue.dart';
import 'models.dart';
import 'teacher_repository.dart';

/// 담당 반 목록 (기관이 바뀌면 다시 읽는다)
final classesProvider = FutureProvider.autoDispose<List<Classroom>>((ref) {
  ref.watch(authControllerProvider.select((s) => s.institutionId));
  return ref.watch(teacherRepositoryProvider).classes();
});

/// 하원 목적지 (SET-002 순서 그대로)
final destinationsProvider = FutureProvider.autoDispose<List<Destination>>((ref) {
  ref.watch(authControllerProvider.select((s) => s.institutionId));
  return ref.watch(teacherRepositoryProvider).destinations();
});

/// 반의 오늘 출결. 등·하원은 낙관적으로 먼저 바꾸고, 실패하면 되돌린다 (스펙 6장).
class ClassAttendanceController extends AutoDisposeFamilyAsyncNotifier<List<Attendance>, String> {
  late String _classId;

  TeacherRepository get _repo => ref.read(teacherRepositoryProvider);

  @override
  Future<List<Attendance>> build(String classId) {
    _classId = classId;
    return _overlay(await _repo.daily(classId, DateTime.now()));
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async => _overlay(await _repo.daily(_classId, DateTime.now())));
  }

  /// 서버 응답 위에, 아직 못 보낸 오프라인 큐 항목을 얹어서 보여 준다 (보낸 뒤엔 서버 값이 이긴다)
  List<Attendance> _overlay(List<Attendance> rows) {
    final queued = ref.read(attendanceQueueProvider.notifier).forClass(_classId);
    if (queued.isEmpty) return rows;
    queued.sort((a, b) => a.clientAt.compareTo(b.clientAt));
    return [
      for (final r in rows)
        () {
          final mine = queued.where((q) => q.studentId == r.studentId).toList();
          if (mine.isEmpty) return r;
          var a = r;
          for (final q in mine) {
            a = a.optimistic(q.isCheckIn ? AttendanceStatus.inClass : AttendanceStatus.out, destinationName: q.destinationName);
          }
          return a.asQueued();
        }(),
    ];
  }

  /// 등원. 서버가 거절하면 원래 행으로 되돌리고 오류를 던진다 (화면이 스낵바로 알림).
  /// 네트워크가 없으면 되돌리지 않고 오프라인 큐에 쌓는다 (연결되면 자동 전송).
  Future<void> checkIn(Attendance a) {
    final item = _item('CHECK_IN', a);
    return _optimistic(a, a.optimistic(AttendanceStatus.inClass), item, () => _repo.checkIn(a, key: item.key, clientAt: item.clientAt));
  }

  Future<void> checkOut(Attendance a, Destination to) {
    final item = _item('CHECK_OUT', a, dest: to);
    return _optimistic(
      a,
      a.optimistic(AttendanceStatus.out, destinationName: to.name),
      item,
      () => _repo.checkOut(a, to, key: item.key, clientAt: item.clientAt),
    );
  }

  QueuedAttendance _item(String type, Attendance a, {Destination? dest}) {
    final auth = ref.read(authControllerProvider);
    return QueuedAttendance(
      key: ApiClient.newIdempotencyKey(),
      type: type,
      studentId: a.studentId,
      studentName: a.studentName,
      classroomId: a.classroomId,
      destinationId: dest?.id,
      destinationName: dest?.name,
      clientAt: DateTime.now().toUtc(),
      userId: auth.user?.id ?? '',
      institutionId: auth.institutionId ?? '',
    );
  }

  Future<void> changeStatus(Attendance a, AttendanceStatus to, String reason, {bool? isLate, bool? isEarlyLeave}) async {
    final saved = await _repo.changeStatus(a.dayId!, to, reason, isLate: isLate, isEarlyLeave: isEarlyLeave);
    _replace(saved);
  }

  /// STOMP attendance.updated — 다른 교사·관리자 웹이 바꾼 것도 바로 반영
  void applyRealtime(Map<String, dynamic> m) {
    if (m['type'] != 'attendance.updated' || m['classroomId'] != _classId) return;
    final rows = state.valueOrNull;
    if (rows == null) return;
    final i = rows.indexWhere((r) => r.studentId == m['studentId']);
    if (i < 0) {
      // 오늘 새로 배정된 원생 등 — 목록을 다시 읽는다
      reload();
      return;
    }
    if (rows[i].pending || rows[i].queued) return; // 내 요청의 응답·대기 중인 큐가 곧 덮어쓴다
    _replace(rows[i].mergeRealtime(m));
  }

  Future<void> _optimistic(Attendance before, Attendance after, QueuedAttendance item, Future<Attendance> Function() send) async {
    final queue = ref.read(attendanceQueueProvider.notifier);
    // 이 원생의 앞선 건이 아직 큐에 있으면 순서(등원 → 하원)를 지키려고 같이 큐에 넣는다
    if (queue.hasFor(before.studentId)) {
      await queue.enqueue(item);
      _replace(after.asQueued());
      unawaited(queue.flush());
      return;
    }
    _replace(after);
    try {
      final saved = await send();
      // 응답에 dayId 가 없을 수 없지만, 혹시 비어 있으면 이전 값을 유지
      _replace(saved.dayId == null && before.dayId != null ? Attendance.fromJson({..._toJson(saved), 'dayId': before.dayId}) : saved);
      // 연결이 돌아왔으니 밀린 것도 보내 본다
      if (ref.read(attendanceQueueProvider).isNotEmpty) unawaited(queue.flush());
    } catch (e) {
      if (ApiException.from(e).isNetwork) {
        await queue.enqueue(item);
        _replace(after.asQueued());
        return;
      }
      _replace(before);
      rethrow;
    }
  }

  void _replace(Attendance a) {
    final rows = state.valueOrNull;
    if (rows == null) return;
    state = AsyncData([for (final r in rows) r.studentId == a.studentId ? a : r]);
  }

  static Map<String, dynamic> _toJson(Attendance a) => {
        'studentId': a.studentId,
        'studentName': a.studentName,
        'classroomId': a.classroomId,
        'status': a.status.api,
        'isLate': a.isLate,
        'isEarlyLeave': a.isEarlyLeave,
        'dayId': a.dayId,
        'checkInAt': a.checkInAt?.toUtc().toIso8601String(),
        'checkOutAt': a.checkOutAt?.toUtc().toIso8601String(),
        'nextDestinationName': a.nextDestinationName,
        'absenceReason': a.absenceReason,
      };
}

final classAttendanceProvider =
    AsyncNotifierProvider.autoDispose.family<ClassAttendanceController, List<Attendance>, String>(ClassAttendanceController.new);
