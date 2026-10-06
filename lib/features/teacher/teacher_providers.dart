import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
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
    return _repo.daily(classId, DateTime.now());
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _repo.daily(_classId, DateTime.now()));
  }

  /// 등원. 실패하면 원래 행으로 되돌리고 오류를 던진다 (화면이 스낵바로 알림)
  Future<void> checkIn(Attendance a) => _optimistic(a, a.optimistic(AttendanceStatus.inClass), () => _repo.checkIn(a));

  Future<void> checkOut(Attendance a, Destination to) =>
      _optimistic(a, a.optimistic(AttendanceStatus.out, destinationName: to.name), () => _repo.checkOut(a, to));

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
    if (rows[i].pending) return; // 내 요청의 응답이 곧 덮어쓴다
    _replace(rows[i].mergeRealtime(m));
  }

  Future<void> _optimistic(Attendance before, Attendance after, Future<Attendance> Function() send) async {
    _replace(after);
    try {
      final saved = await send();
      // 응답에 dayId 가 없을 수 없지만, 혹시 비어 있으면 이전 값을 유지
      _replace(saved.dayId == null && before.dayId != null ? Attendance.fromJson({..._toJson(saved), 'dayId': before.dayId}) : saved);
    } catch (e) {
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
