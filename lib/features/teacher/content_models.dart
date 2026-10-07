import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../parent/models.dart' show FileAttachment;

/// 교사앱 알림장·행사 모델 (NTC·EVT). 필드명은 백엔드 JSON 과 같다.

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// 발송 대상 한 칸 — 전체(ALL) / 반(CLASS) / 원생(STUDENT)
class Target {
  const Target({required this.scope, this.id, this.name});

  static const all = Target(scope: 'ALL', name: '전체');

  final String scope;
  final String? id;
  final String? name;

  bool get isAll => scope == 'ALL';

  factory Target.fromJson(Map<String, dynamic> j) => Target(scope: j['scope'] as String, id: j['id'] as String?, name: j['name'] as String?);

  /// 요청 본문용 (name 제외)
  Map<String, dynamic> toRequest() => {'scope': scope, 'id': id};

  @override
  bool operator ==(Object other) => other is Target && other.scope == scope && other.id == id;

  @override
  int get hashCode => Object.hash(scope, id);
}

/// "전체" / "햇살반" / "햇살반 외 2"
String targetSummary(List<Target> targets) {
  if (targets.any((t) => t.isAll)) return '전체';
  if (targets.isEmpty) return '-';
  final first = targets.first.name ?? '';
  return targets.length == 1 ? first : '$first 외 ${targets.length - 1}';
}

/// 페이지 응답 {items, page, size, totalElements, totalPages}
class PageOf<T> {
  const PageOf({required this.items, required this.page, required this.totalPages});

  final List<T> items;
  final int page;
  final int totalPages;

  bool get hasMore => page + 1 < totalPages;

  factory PageOf.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) f) => PageOf(
        items: (j['items'] as List).map((e) => f(e as Map<String, dynamic>)).toList(),
        page: j['page'] as int,
        totalPages: j['totalPages'] as int,
      );
}

/// 원생 검색 결과 (GET /students)
class StudentRef {
  const StudentRef({required this.id, required this.name});

  final String id;
  final String name;

  factory StudentRef.fromJson(Map<String, dynamic> j) => StudentRef(id: j['id'] as String, name: j['name'] as String);
}

// ───────── 알림장 ─────────

enum NoticeKind {
  note,
  announcement;

  static NoticeKind parse(String v) => v == 'ANNOUNCEMENT' ? NoticeKind.announcement : NoticeKind.note;

  String get api => this == NoticeKind.announcement ? 'ANNOUNCEMENT' : 'NOTE';
  String get label => this == NoticeKind.announcement ? '공지' : '알림장';
}

enum NoticeStatus {
  scheduled,
  sent,
  canceled;

  String get api => switch (this) {
        NoticeStatus.scheduled => 'SCHEDULED',
        NoticeStatus.sent => 'SENT',
        NoticeStatus.canceled => 'CANCELED',
      };

  static NoticeStatus parse(String v) => switch (v) {
        'SENT' => NoticeStatus.sent,
        'CANCELED' => NoticeStatus.canceled,
        _ => NoticeStatus.scheduled,
      };

  String get label => switch (this) {
        NoticeStatus.scheduled => '예약',
        NoticeStatus.sent => '발송',
        NoticeStatus.canceled => '취소',
      };

  Color get color => switch (this) {
        NoticeStatus.scheduled => AppColors.info,
        NoticeStatus.sent => AppColors.success,
        NoticeStatus.canceled => AppColors.muted,
      };
}

/// 열람 현황. rate 는 0~1 비율 (대시보드의 noticeReadRate 와 달리 % 가 아님)
class ReadStats {
  const ReadStats({required this.targetStudents, required this.readStudents, this.rate});

  final int targetStudents;
  final int readStudents;
  final double? rate;

  factory ReadStats.fromJson(Map<String, dynamic> j) => ReadStats(
        targetStudents: (j['targetStudents'] as num).toInt(),
        readStudents: (j['readStudents'] as num).toInt(),
        rate: (j['rate'] as num?)?.toDouble(),
      );

  int get unread => targetStudents - readStudents;
}

class TeacherNotice {
  const TeacherNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.pinned,
    required this.targets,
    required this.status,
    required this.authorId,
    required this.authorName,
    this.scheduledAt,
    this.sentAt,
    this.lastResentAt,
    this.createdAt,
    this.readStats,
    this.attachments = const [],
  });

  final String id;
  final NoticeKind kind;
  final String title;
  final String body;
  final bool pinned;
  final List<Target> targets;
  final NoticeStatus status;
  final String authorId;
  final String authorName;
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final DateTime? lastResentAt;
  final DateTime? createdAt;
  final ReadStats? readStats;
  final List<FileAttachment> attachments;

  factory TeacherNotice.fromJson(Map<String, dynamic> j) {
    final author = j['author'] as Map<String, dynamic>;
    return TeacherNotice(
      id: j['id'] as String,
      kind: NoticeKind.parse(j['kind'] as String),
      title: j['title'] as String,
      body: j['body'] as String? ?? '',
      pinned: j['pinned'] as bool? ?? false,
      targets: (j['targets'] as List? ?? const []).map((e) => Target.fromJson(e as Map<String, dynamic>)).toList(),
      status: NoticeStatus.parse(j['status'] as String),
      authorId: author['id'] as String,
      authorName: author['name'] as String,
      scheduledAt: _time(j['scheduledAt']),
      sentAt: _time(j['sentAt']),
      lastResentAt: _time(j['lastResentAt']),
      createdAt: _time(j['createdAt']),
      readStats: j['readStats'] == null ? null : ReadStats.fromJson(j['readStats'] as Map<String, dynamic>),
      attachments: (j['attachments'] as List? ?? const []).map((e) => FileAttachment.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// 목록에 보여 줄 시각: 발송했으면 발송 시각, 예약이면 예약 시각
  DateTime? get when => sentAt ?? scheduledAt ?? createdAt;
}

/// 작성·수정 요청 내용
class NoticeDraft {
  const NoticeDraft({
    required this.kind,
    required this.title,
    required this.body,
    required this.pinned,
    required this.targets,
    required this.attachmentIds,
    this.sendAt,
  });

  final NoticeKind kind;
  final String title;
  final String body;
  final bool pinned;
  final List<Target> targets;
  final List<String> attachmentIds;

  /// null 이면 즉시 발송
  final DateTime? sendAt;

  Map<String, dynamic> toJson() => {
        'kind': kind.api,
        'title': title,
        'body': body,
        'pinned': pinned,
        'targets': targets.map((t) => t.toRequest()).toList(),
        'sendAt': sendAt?.toUtc().toIso8601String(),
        'attachments': attachmentIds,
      };
}

class ReceiptStudent {
  const ReceiptStudent({
    required this.studentId,
    required this.studentName,
    required this.classroomNames,
    required this.read,
    required this.appLinked,
    required this.resentCount,
    this.firstReadAt,
  });

  final String studentId;
  final String studentName;
  final List<String> classroomNames;
  final bool read;
  final bool appLinked;
  final int resentCount;
  final DateTime? firstReadAt;

  factory ReceiptStudent.fromJson(Map<String, dynamic> j) => ReceiptStudent(
        studentId: j['studentId'] as String,
        studentName: j['studentName'] as String,
        classroomNames: (j['classroomNames'] as List? ?? const []).cast<String>(),
        read: j['read'] as bool? ?? false,
        appLinked: j['appLinked'] as bool? ?? false,
        resentCount: (j['resentCount'] as num?)?.toInt() ?? 0,
        firstReadAt: _time(j['firstReadAt']),
      );
}

/// NTC-005 수신 확인
class NoticeReceipts {
  const NoticeReceipts({required this.stats, required this.students, this.canResendAt});

  final ReadStats stats;
  final List<ReceiptStudent> students;

  /// 이 시각 이후에 미열람 재발송 가능 (30분 쿨타임). null 이면 바로 가능
  final DateTime? canResendAt;

  factory NoticeReceipts.fromJson(Map<String, dynamic> j) => NoticeReceipts(
        stats: ReadStats.fromJson(j['stats'] as Map<String, dynamic>),
        students: (j['students'] as List).map((e) => ReceiptStudent.fromJson(e as Map<String, dynamic>)).toList(),
        canResendAt: _time(j['canResendAt']),
      );
}

// ───────── 행사 ─────────

class Tally {
  const Tally({required this.targets, required this.attend, required this.absent, required this.pending});

  final int targets;
  final int attend;
  final int absent;
  final int pending;

  factory Tally.fromJson(Map<String, dynamic> j) => Tally(
        targets: (j['targets'] as num).toInt(),
        attend: (j['attend'] as num).toInt(),
        absent: (j['absent'] as num).toInt(),
        pending: (j['pending'] as num).toInt(),
      );
}

class SchoolEvent {
  const SchoolEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.targets,
    required this.rsvpEnabled,
    required this.canceled,
    required this.authorName,
    this.body,
    this.location,
    this.endsAt,
    this.rsvpDeadline,
    this.reminderHoursBefore,
    this.remindedAt,
    this.tally,
  });

  final String id;
  final String title;
  final String? body;
  final String? location;
  final DateTime startsAt;
  final DateTime? endsAt;
  final List<Target> targets;
  final bool rsvpEnabled;
  final DateTime? rsvpDeadline;
  final int? reminderHoursBefore;
  final DateTime? remindedAt;
  final bool canceled;
  final String authorName;
  final Tally? tally;

  factory SchoolEvent.fromJson(Map<String, dynamic> j) => SchoolEvent(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        location: j['location'] as String?,
        startsAt: _time(j['startsAt'])!,
        endsAt: _time(j['endsAt']),
        targets: (j['targets'] as List? ?? const []).map((e) => Target.fromJson(e as Map<String, dynamic>)).toList(),
        rsvpEnabled: j['rsvpEnabled'] as bool? ?? false,
        rsvpDeadline: _time(j['rsvpDeadline']),
        reminderHoursBefore: (j['reminderHoursBefore'] as num?)?.toInt(),
        remindedAt: _time(j['remindedAt']),
        canceled: j['status'] == 'CANCELED',
        authorName: j['authorName'] as String? ?? '',
        tally: j['tally'] == null ? null : Tally.fromJson(j['tally'] as Map<String, dynamic>),
      );

  bool get deadlinePassed => rsvpDeadline != null && rsvpDeadline!.isBefore(DateTime.now());
}

/// 행사 생성·수정 요청 내용. 수정에는 대상·RSVP 사용 여부가 들어가지 않는다 (백엔드 UpdateRequest).
class EventDraft {
  const EventDraft({
    required this.title,
    required this.startsAt,
    required this.rsvpEnabled,
    this.body,
    this.location,
    this.endsAt,
    this.targets = const [],
    this.rsvpDeadline,
    this.reminderHoursBefore,
  });

  final String title;
  final String? body;
  final String? location;
  final DateTime startsAt;
  final DateTime? endsAt;
  final List<Target> targets;
  final bool rsvpEnabled;
  final DateTime? rsvpDeadline;
  final int? reminderHoursBefore;

  Map<String, dynamic> toCreateJson() => {
        'title': title,
        'body': body,
        'location': location,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'targets': targets.map((t) => t.toRequest()).toList(),
        'rsvpEnabled': rsvpEnabled,
        'rsvpDeadline': rsvpEnabled ? rsvpDeadline?.toUtc().toIso8601String() : null,
        'reminderHoursBefore': rsvpEnabled ? reminderHoursBefore : null,
      };

  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'body': body,
        'location': location,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'rsvpDeadline': rsvpDeadline?.toUtc().toIso8601String(),
        'reminderHoursBefore': reminderHoursBefore ?? 24,
      };
}

enum RsvpAnswer {
  attend,
  absent;

  static RsvpAnswer? parse(String? v) => switch (v) {
        'ATTEND' => RsvpAnswer.attend,
        'ABSENT' => RsvpAnswer.absent,
        _ => null,
      };

  String get label => this == RsvpAnswer.attend ? '참석' : '불참';
  Color get color => this == RsvpAnswer.attend ? AppColors.success : AppColors.error;
}

class RsvpRow {
  const RsvpRow({
    required this.studentId,
    required this.studentName,
    required this.classroomNames,
    this.answer,
    this.reason,
    this.respondedAt,
    this.respondedByName,
  });

  final String studentId;
  final String studentName;
  final List<String> classroomNames;
  final RsvpAnswer? answer;
  final String? reason;
  final DateTime? respondedAt;
  final String? respondedByName;

  factory RsvpRow.fromJson(Map<String, dynamic> j) => RsvpRow(
        studentId: j['studentId'] as String,
        studentName: j['studentName'] as String,
        classroomNames: (j['classroomNames'] as List? ?? const []).cast<String>(),
        answer: RsvpAnswer.parse(j['answer'] as String?),
        reason: j['reason'] as String?,
        respondedAt: _time(j['respondedAt']),
        respondedByName: j['respondedByName'] as String?,
      );
}

/// EVT-003 응답 집계 + 명단 (미응답 먼저)
class EventSummary {
  const EventSummary({required this.event, required this.tally, required this.rows});

  final SchoolEvent event;
  final Tally tally;
  final List<RsvpRow> rows;

  factory EventSummary.fromJson(Map<String, dynamic> j) => EventSummary(
        event: SchoolEvent.fromJson(j['event'] as Map<String, dynamic>),
        tally: Tally.fromJson(j['tally'] as Map<String, dynamic>),
        rows: (j['rows'] as List).map((e) => RsvpRow.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
