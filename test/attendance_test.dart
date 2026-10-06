import 'package:flutter_test/flutter_test.dart';
import 'package:ttokttok_app/core/widgets/status_badge.dart';
import 'package:ttokttok_app/features/teacher/models.dart';

void main() {
  test('상태 4개 + 플래그 2개 → 표시 라벨 (관리자 웹과 같은 규칙)', () {
    expect(attendanceLabel(AttendanceStatus.scheduled).label, '등원 전');
    expect(attendanceLabel(AttendanceStatus.inClass, isLate: true).label, '등원(지각)');
    expect(attendanceLabel(AttendanceStatus.out, isEarlyLeave: true).label, '하원(조퇴)');
    expect(attendanceLabel(AttendanceStatus.out, isLate: true, isEarlyLeave: true).label, '하원(지각·조퇴)');
  });

  test('STOMP attendance.updated 를 기존 행에 덮어도 dayId 는 유지', () {
    final a = Attendance.fromJson({
      'studentId': 's1', 'studentName': '김하늘', 'classroomId': 'c1', 'status': 'SCHEDULED',
      'isLate': false, 'isEarlyLeave': false, 'dayId': 'd1',
    });
    final b = a.mergeRealtime({'type': 'attendance.updated', 'status': 'IN', 'isLate': true, 'checkInAt': '2026-10-05T05:10:00Z'});
    expect(b.status, AttendanceStatus.inClass);
    expect(b.isLate, true);
    expect(b.dayId, 'd1');
  });
}
