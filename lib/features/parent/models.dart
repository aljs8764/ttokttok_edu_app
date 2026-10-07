/// 학부모앱 응답 모델 (/me/* — 기관 헤더 없이 소속 전 기관을 가로지른다)

DateTime? _t(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// 아이 (스펙 7-8). 다자녀 = 아이 여러 명, 한 아이가 여러 학원·학교 = enrollments 여러 개.
/// 상단 자녀 선택·목록 필터는 아이 id 로 한다 (서버가 그 아이의 모든 기관으로 펼친다).
class Child {
  const Child({required this.childId, required this.name, required this.enrollments});

  final String childId;
  final String name;
  final List<Enrollment> enrollments;

  /// "수학학원 · 영어학원"
  String get institutionsLabel => enrollments.map((e) => e.institutionName).join(' · ');

  bool hasStudent(String studentId) => enrollments.any((e) => e.studentId == studentId);

  factory Child.fromJson(Map<String, dynamic> j) => Child(
        childId: j['childId'] as String,
        name: j['name'] as String,
        enrollments: (j['enrollments'] as List).map((e) => Enrollment.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// 아이가 다니는 기관 하나 (기관이 관리하는 원생 기록)
class Enrollment {
  const Enrollment({
    required this.studentId,
    required this.studentName,
    required this.institutionId,
    required this.institutionName,
    required this.institutionType,
    required this.status,
  });

  final String studentId;
  final String studentName;
  final String institutionId;
  final String institutionName;

  /// ACADEMY | SCHOOL | DAYCARE | OTHER
  final String institutionType;

  /// ACTIVE | PAUSED | WITHDRAWN
  final String status;

  String get typeLabel => switch (institutionType) {
        'SCHOOL' => '학교',
        'DAYCARE' => '어린이집',
        'OTHER' => '기관',
        _ => '학원',
      };

  factory Enrollment.fromJson(Map<String, dynamic> j) => Enrollment(
        studentId: j['studentId'] as String,
        studentName: j['studentName'] as String,
        institutionId: j['institutionId'] as String,
        institutionName: j['institutionName'] as String,
        institutionType: j['institutionType'] as String? ?? 'ACADEMY',
        status: j['status'] as String? ?? 'ACTIVE',
      );
}

/// 같은 아이로 보이는 묶음 — "같은 아이인가요?" (GET /me/children/merge-suggestions)
class MergeSuggestion {
  const MergeSuggestion({required this.childIds, required this.name, required this.institutionNames});

  final List<String> childIds;
  final String name;
  final List<String> institutionNames;

  /// 앱에서 "다른 아이예요"를 눌렀을 때 기억하는 키
  String get key => ([...childIds]..sort()).join(',');

  factory MergeSuggestion.fromJson(Map<String, dynamic> j) => MergeSuggestion(
        childIds: (j['childIds'] as List).cast<String>(),
        name: j['name'] as String,
        institutionNames: (j['institutionNames'] as List).cast<String>(),
      );
}

/// PAR-001 통합 안심 타임라인 한 줄 (등원·하원·상태 변경)
class TimelineItem {
  const TimelineItem({
    required this.studentId,
    this.childId,
    required this.studentName,
    required this.institutionName,
    required this.type,
    required this.status,
    required this.isLate,
    required this.occurredAt,
    this.destinationName,
  });

  final String studentId;
  final String? childId;
  final String studentName;
  final String institutionName;

  /// CHECK_IN | CHECK_OUT | STATUS_CHANGE
  final String type;

  /// SCHEDULED | IN | OUT | ABSENT
  final String status;
  final bool isLate;
  final String? destinationName;
  final DateTime occurredAt;

  factory TimelineItem.fromJson(Map<String, dynamic> j) => TimelineItem(
        studentId: j['studentId'] as String,
        childId: j['childId'] as String?,
        studentName: j['studentName'] as String,
        institutionName: j['institutionName'] as String,
        type: j['type'] as String,
        status: j['status'] as String,
        isLate: j['isLate'] as bool? ?? false,
        destinationName: j['destinationName'] as String?,
        occurredAt: _t(j['occurredAt'])!,
      );

  /// 학부모에게 보이는 문장 — "도착했어요" / "출발했어요 → 셔틀 1호차"
  String get headline => switch (type) {
        'CHECK_IN' => isLate ? '$institutionName에 도착했어요 (지각)' : '$institutionName에 도착했어요',
        'CHECK_OUT' => destinationName != null ? '$institutionName에서 출발했어요 → $destinationName' : '$institutionName에서 출발했어요',
        _ => switch (status) {
            'ABSENT' => '$institutionName 결석으로 처리됐어요',
            'IN' => '$institutionName 등원으로 정정됐어요',
            'OUT' => '$institutionName 하원으로 정정됐어요',
            _ => '$institutionName 출결이 바뀌었어요',
          },
      };
}

class FileAttachment {
  const FileAttachment({required this.id, required this.name, required this.mime, required this.size, this.downloadUrl});

  final String id;
  final String name;
  final String mime;
  final int size;

  /// 5분 만료 서명 URL (상세 조회 때만 채워진다)
  final String? downloadUrl;

  factory FileAttachment.fromJson(Map<String, dynamic> j) => FileAttachment(
        id: j['id'] as String,
        name: j['name'] as String,
        mime: j['mime'] as String,
        size: (j['size'] as num).toInt(),
        downloadUrl: j['downloadUrl'] as String?,
      );

  bool get isImage => mime.startsWith('image/');
}

/// PAR-004 알림장함 항목
class ParentNotice {
  const ParentNotice({
    required this.id,
    required this.institutionName,
    required this.kind,
    required this.title,
    required this.body,
    required this.pinned,
    required this.children,
    required this.authorName,
    required this.attachments,
    this.sentAt,
    this.readAt,
  });

  final String id;
  final String institutionName;

  /// NOTE | ANNOUNCEMENT
  final String kind;
  final String title;
  final String body;
  final bool pinned;
  final List<String> children;
  final String authorName;
  final List<FileAttachment> attachments;
  final DateTime? sentAt;
  final DateTime? readAt;

  bool get unread => readAt == null;
  bool get isAnnouncement => kind == 'ANNOUNCEMENT';

  factory ParentNotice.fromJson(Map<String, dynamic> j) => ParentNotice(
        id: j['id'] as String,
        institutionName: j['institutionName'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        pinned: j['pinned'] as bool? ?? false,
        children: (j['children'] as List).map((c) => (c as Map)['name'] as String).toList(),
        authorName: j['authorName'] as String? ?? '',
        attachments: (j['attachments'] as List? ?? const []).map((a) => FileAttachment.fromJson(a as Map<String, dynamic>)).toList(),
        sentAt: _t(j['sentAt']),
        readAt: _t(j['readAt']),
      );

  ParentNotice markRead() => ParentNotice(
        id: id,
        institutionName: institutionName,
        kind: kind,
        title: title,
        body: body,
        pinned: pinned,
        children: children,
        authorName: authorName,
        attachments: attachments,
        sentAt: sentAt,
        readAt: readAt ?? DateTime.now(),
      );
}

class ChildRsvp {
  const ChildRsvp({required this.studentId, required this.name, this.answer, this.reason, this.respondedAt});

  final String studentId;
  final String name;

  /// ATTEND | ABSENT | null(미응답)
  final String? answer;
  final String? reason;
  final DateTime? respondedAt;

  factory ChildRsvp.fromJson(Map<String, dynamic> j) => ChildRsvp(
        studentId: j['studentId'] as String,
        name: j['name'] as String,
        answer: j['answer'] as String?,
        reason: j['reason'] as String?,
        respondedAt: _t(j['respondedAt']),
      );
}

/// PAR-005 행사 + 자녀별 참석 응답
class ParentEvent {
  const ParentEvent({
    required this.id,
    required this.institutionName,
    required this.title,
    required this.startsAt,
    required this.status,
    required this.rsvpEnabled,
    required this.open,
    required this.children,
    this.body,
    this.location,
    this.endsAt,
    this.rsvpDeadline,
  });

  final String id;
  final String institutionName;
  final String title;
  final String? body;
  final String? location;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// ACTIVE | CANCELED
  final String status;
  final bool rsvpEnabled;
  final DateTime? rsvpDeadline;

  /// 아직 응답할 수 있는지 (마감 전·취소 아님)
  final bool open;
  final List<ChildRsvp> children;

  bool get canceled => status == 'CANCELED';
  bool get needsAnswer => rsvpEnabled && open && children.any((c) => c.answer == null);

  factory ParentEvent.fromJson(Map<String, dynamic> j) => ParentEvent(
        id: j['id'] as String,
        institutionName: j['institutionName'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        location: j['location'] as String?,
        startsAt: _t(j['startsAt'])!,
        endsAt: _t(j['endsAt']),
        status: j['status'] as String,
        rsvpEnabled: j['rsvpEnabled'] as bool? ?? false,
        rsvpDeadline: _t(j['rsvpDeadline']),
        open: j['open'] as bool? ?? false,
        children: (j['children'] as List).map((c) => ChildRsvp.fromJson(c as Map<String, dynamic>)).toList(),
      );
}

/// PAR-003 주간 스케줄
class WeekSchedule {
  const WeekSchedule({required this.weekStart, required this.children});

  final DateTime weekStart;
  final List<ChildWeek> children;

  factory WeekSchedule.fromJson(Map<String, dynamic> j) => WeekSchedule(
        weekStart: DateTime.parse(j['weekStart'] as String),
        children: (j['children'] as List).map((c) => ChildWeek.fromJson(c as Map<String, dynamic>)).toList(),
      );
}

class ChildWeek {
  const ChildWeek({required this.studentId, required this.name, required this.days});

  final String studentId;
  final String name;
  final List<DaySchedule> days;

  factory ChildWeek.fromJson(Map<String, dynamic> j) => ChildWeek(
        studentId: j['studentId'] as String,
        name: j['name'] as String,
        days: (j['days'] as List).map((d) => DaySchedule.fromJson(d as Map<String, dynamic>)).toList(),
      );
}

class DaySchedule {
  const DaySchedule({required this.date, required this.items});

  final DateTime date;
  final List<ScheduleItem> items;

  factory DaySchedule.fromJson(Map<String, dynamic> j) => DaySchedule(
        date: DateTime.parse(j['date'] as String),
        items: (j['items'] as List).map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      );
}

class ScheduleItem {
  const ScheduleItem({required this.kind, required this.title, required this.institutionName, this.startsAt, this.endsAt, this.eventId, this.status});

  /// CLASS | EVENT
  final String kind;
  final String title;
  final String institutionName;

  /// CLASS 면 "14:00"(LocalTime), EVENT 면 ISO 시각
  final String? startsAt;
  final String? endsAt;
  final String? eventId;

  /// CLASS 면 그날 출결 상태(있으면)
  final String? status;

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        kind: j['kind'] as String,
        title: j['title'] as String,
        institutionName: j['institutionName'] as String,
        startsAt: j['startsAt']?.toString(),
        endsAt: j['endsAt']?.toString(),
        eventId: j['eventId']?.toString(),
        status: j['status']?.toString(),
      );

  /// "14:00" 또는 ISO → "14:00"
  static String hm(String? v) {
    if (v == null) return '';
    if (v.length <= 8) return v.substring(0, 5);
    final d = DateTime.parse(v).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class Terms {
  const Terms({required this.id, required this.title, required this.body, required this.required, required this.version});

  final String id;
  final String title;
  final String body;
  final bool required;
  final int version;

  factory Terms.fromJson(Map<String, dynamic> j) => Terms(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        required: j['required'] as bool? ?? false,
        version: (j['version'] as num).toInt(),
      );
}
