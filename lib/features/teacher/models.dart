/// 백엔드 응답 모델 (교사앱). 필드명은 백엔드 JSON 과 같다.

enum AttendanceStatus {
  scheduled,
  inClass,
  out,
  absent;

  static AttendanceStatus parse(String v) => switch (v) {
        'IN' => AttendanceStatus.inClass,
        'OUT' => AttendanceStatus.out,
        'ABSENT' => AttendanceStatus.absent,
        _ => AttendanceStatus.scheduled,
      };

  String get api => switch (this) {
        AttendanceStatus.scheduled => 'SCHEDULED',
        AttendanceStatus.inClass => 'IN',
        AttendanceStatus.out => 'OUT',
        AttendanceStatus.absent => 'ABSENT',
      };
}

class Classroom {
  const Classroom({
    required this.id,
    required this.name,
    required this.days,
    required this.startTime,
    required this.endTime,
    this.headcount,
  });

  final String id;
  final String name;
  final List<String> days;
  final String startTime;
  final String endTime;
  final int? headcount;

  factory Classroom.fromJson(Map<String, dynamic> j) => Classroom(
        id: j['id'] as String,
        name: j['name'] as String,
        days: (j['days'] as List).cast<String>(),
        startTime: (j['startTime'] as String).substring(0, 5),
        endTime: (j['endTime'] as String).substring(0, 5),
        headcount: j['headcount'] as int?,
      );

  /// 오늘 수업 요일인지 (DayOfWeek: MONDAY…SUNDAY)
  bool heldOn(DateTime d) => days.contains(const ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'][d.weekday - 1]);
}

class Destination {
  const Destination({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final String type;

  factory Destination.fromJson(Map<String, dynamic> j) => Destination(id: j['id'] as String, name: j['name'] as String, type: j['type'] as String);
}

/// 원생 하루 출결 한 줄 (AttendanceResponse)
class Attendance {
  const Attendance({
    required this.studentId,
    required this.studentName,
    required this.classroomId,
    required this.status,
    required this.isLate,
    required this.isEarlyLeave,
    this.dayId,
    this.checkInAt,
    this.checkOutAt,
    this.nextDestinationName,
    this.absenceReason,
    this.pending = false,
  });

  final String studentId;
  final String studentName;
  final String classroomId;
  final AttendanceStatus status;
  final bool isLate;
  final bool isEarlyLeave;
  final String? dayId;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final String? nextDestinationName;
  final String? absenceReason;

  /// 낙관적 업데이트 후 서버 응답 대기 중
  final bool pending;

  factory Attendance.fromJson(Map<String, dynamic> j) => Attendance(
        studentId: j['studentId'] as String,
        studentName: j['studentName'] as String,
        classroomId: j['classroomId'] as String,
        status: AttendanceStatus.parse(j['status'] as String),
        isLate: j['isLate'] as bool? ?? false,
        isEarlyLeave: j['isEarlyLeave'] as bool? ?? false,
        dayId: j['dayId'] as String?,
        checkInAt: _time(j['checkInAt']),
        checkOutAt: _time(j['checkOutAt']),
        nextDestinationName: j['nextDestinationName'] as String?,
        absenceReason: j['absenceReason'] as String?,
      );

  /// STOMP attendance.updated 메시지를 기존 행에 덮는다 (dayId 는 메시지에 없어서 유지)
  Attendance mergeRealtime(Map<String, dynamic> m) => Attendance(
        studentId: studentId,
        studentName: studentName,
        classroomId: classroomId,
        status: AttendanceStatus.parse(m['status'] as String),
        isLate: m['isLate'] as bool? ?? isLate,
        isEarlyLeave: m['isEarlyLeave'] as bool? ?? isEarlyLeave,
        dayId: dayId,
        checkInAt: _time(m['checkInAt']),
        checkOutAt: _time(m['checkOutAt']),
        nextDestinationName: m['nextDestinationName'] as String?,
        absenceReason: absenceReason,
      );

  Attendance optimistic(AttendanceStatus to, {String? destinationName}) => Attendance(
        studentId: studentId,
        studentName: studentName,
        classroomId: classroomId,
        status: to,
        isLate: isLate,
        isEarlyLeave: isEarlyLeave,
        dayId: dayId,
        checkInAt: to == AttendanceStatus.inClass ? DateTime.now() : checkInAt,
        checkOutAt: to == AttendanceStatus.out ? DateTime.now() : checkOutAt,
        nextDestinationName: destinationName ?? nextDestinationName,
        absenceReason: absenceReason,
        pending: true,
      );

  static DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
}
