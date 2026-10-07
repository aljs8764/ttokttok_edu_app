import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import 'attendance_queue.dart' show BulkResult, QueuedAttendance;
import 'models.dart';

/// 교사앱 API. 쓰기(등·하원)는 Idempotency-Key + clientAt 을 붙이고, 네트워크 오류면 같은 키로 재시도한다.
class TeacherRepository {
  TeacherRepository(this._api);

  final ApiClient _api;
  Dio get _dio => _api.dio;

  static final _date = DateFormat('yyyy-MM-dd');

  /// 교사는 담당 반만 내려온다 (원장·실장은 전체)
  Future<List<Classroom>> classes() => _call(() async {
        final r = await _dio.get<List<dynamic>>('classes');
        return r.data!.map((e) => Classroom.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<List<Attendance>> daily(String classId, DateTime date) => _call(() async {
        final r = await _dio.get<List<dynamic>>('attendance/daily', queryParameters: {'classId': classId, 'date': _date.format(date)});
        final list = r.data!.map((e) => Attendance.fromJson(e as Map<String, dynamic>)).toList();
        list.sort((a, b) => a.studentName.compareTo(b.studentName));
        return list;
      });

  Future<List<Destination>> destinations() => _call(() async {
        final r = await _dio.get<List<dynamic>>('destinations');
        return r.data!.map((e) => Destination.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// ATT-005 원터치 등원. [key]·[clientAt] 은 호출하는 쪽이 정한다 — 네트워크가 끊겨 오프라인 큐로 넘길 때 같은 값을 써야 중복 처리가 안 된다.
  Future<Attendance> checkIn(Attendance a, {required String key, required DateTime clientAt}) => _write(
        'attendance/check-in',
        {'studentId': a.studentId, 'classroomId': a.classroomId, 'clientAt': clientAt.toUtc().toIso8601String()},
        key,
      );

  /// ATT-006 하원 + 다음 목적지
  Future<Attendance> checkOut(Attendance a, Destination to, {required String key, required DateTime clientAt}) => _write(
        'attendance/check-out',
        {'studentId': a.studentId, 'classroomId': a.classroomId, 'destinationId': to.id, 'clientAt': clientAt.toUtc().toIso8601String()},
        key,
      );

  /// 오프라인 큐 일괄 전송 (최대 100건). 서버가 clientAt 순으로 처리하고 항목별 결과를 돌려준다.
  Future<List<BulkResult>> bulk(List<QueuedAttendance> items) => _call(() async {
        final r = await _dio.post<List<dynamic>>('attendance/bulk', data: {'items': [for (final q in items) q.toBulkJson()]});
        return r.data!.map((e) => BulkResult.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// ATT-002 수동 변경 (사유 필수). 잘못 누른 등원 되돌리기 등.
  Future<Attendance> changeStatus(String dayId, AttendanceStatus to, String reason, {bool? isLate, bool? isEarlyLeave}) => _call(() async {
        final r = await _dio.patch<Map<String, dynamic>>('attendance/$dayId/status', data: {
          'status': to.api,
          'source': 'TEACHER_APP',
          'reason': reason,
          'isLate': to == AttendanceStatus.absent ? null : isLate,
          'isEarlyLeave': to == AttendanceStatus.out ? isEarlyLeave : null,
        });
        return Attendance.fromJson(r.data!);
      });

  /// 같은 키로 최대 3번 (0.5s, 1s 간격). 서버가 같은 키를 이미 처리했으면 그 결과를 돌려준다.
  Future<Attendance> _write(String path, Map<String, dynamic> body, String key) async {
    for (var attempt = 0;; attempt++) {
      try {
        final r = await _dio.post<Map<String, dynamic>>(path, data: body, options: Options(headers: {'Idempotency-Key': key}));
        return Attendance.fromJson(r.data!);
      } catch (e) {
        final err = ApiException.from(e);
        if (!err.isNetwork || attempt >= 2) throw err;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final teacherRepositoryProvider = Provider<TeacherRepository>((ref) => TeacherRepository(ref.watch(apiClientProvider)));
