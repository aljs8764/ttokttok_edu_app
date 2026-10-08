import '../parent/models.dart' show FileAttachment;

DateTime? _t(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// NTC-007·008 대화방 (알림장 회신 포함)
class Conversation {
  const Conversation({
    required this.id,
    required this.institutionName,
    required this.studentId,
    required this.studentName,
    required this.guardianName,
    required this.unread,
    this.noticeId,
    this.noticeTitle,
    this.lastMessageAt,
    this.lastMessagePreview,
  });

  final String id;
  final String institutionName;
  final String studentId;
  final String studentName;
  final String guardianName;
  final int unread;
  final String? noticeId;
  final String? noticeTitle;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final notice = j['notice'] as Map<String, dynamic>?;
    return Conversation(
      id: j['id'] as String,
      institutionName: j['institutionName'] as String? ?? '',
      studentId: j['studentId'] as String,
      studentName: j['studentName'] as String? ?? '',
      guardianName: (j['guardian'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      noticeId: notice?['id'] as String?,
      noticeTitle: notice?['title'] as String?,
      lastMessageAt: _t(j['lastMessageAt']),
      lastMessagePreview: j['lastMessagePreview'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.id, required this.senderName, required this.fromStaff, required this.body, required this.createdAt});

  final String id;
  final String senderName;
  final bool fromStaff;
  final String body;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        senderName: j['senderName'] as String? ?? '',
        fromStaff: j['side'] == 'STAFF',
        body: j['body'] as String,
        createdAt: _t(j['createdAt'])!,
      );
}

/// ATT-007
class AbsenceRequest {
  const AbsenceRequest({
    required this.id,
    required this.institutionName,
    required this.studentName,
    required this.guardianName,
    required this.date,
    required this.kind,
    required this.reason,
    required this.status,
    this.expectedTime,
  });

  final String id;
  final String institutionName;
  final String studentName;
  final String guardianName;
  final DateTime date;

  /// ABSENT | LATE | EARLY_LEAVE
  final String kind;
  final String reason;

  /// SUBMITTED | ACKNOWLEDGED | CANCELLED
  final String status;
  final String? expectedTime;

  String get kindLabel => const {'ABSENT': '결석', 'LATE': '지각', 'EARLY_LEAVE': '조퇴'}[kind] ?? kind;
  String get statusLabel => const {'SUBMITTED': '확인 대기', 'ACKNOWLEDGED': '확인함', 'CANCELLED': '취소'}[status] ?? status;

  factory AbsenceRequest.fromJson(Map<String, dynamic> j) => AbsenceRequest(
        id: j['id'] as String,
        institutionName: j['institutionName'] as String? ?? '',
        studentName: j['studentName'] as String? ?? '',
        guardianName: j['guardianName'] as String? ?? '',
        date: DateTime.parse(j['date'] as String),
        kind: j['kind'] as String,
        reason: j['reason'] as String? ?? '',
        status: j['status'] as String,
        expectedTime: (j['expectedTime'] as String?)?.substring(0, 5),
      );
}

class SurveyQuestion {
  const SurveyQuestion({required this.id, required this.type, required this.text, required this.options, required this.required});

  final String id;

  /// SINGLE | MULTI | TEXT | RATING
  final String type;
  final String text;
  final List<String> options;
  final bool required;

  factory SurveyQuestion.fromJson(Map<String, dynamic> j) => SurveyQuestion(
        id: j['id'] as String,
        type: j['type'] as String,
        text: j['text'] as String,
        options: (j['options'] as List? ?? const []).cast<String>(),
        required: j['required'] as bool? ?? true,
      );
}

class SurveyChild {
  const SurveyChild({required this.studentId, required this.name, required this.answered});
  final String studentId;
  final String name;
  final bool answered;
}

/// NTC-010 학부모 앱의 설문 한 건 (자녀별 응답 여부 포함)
class ParentSurvey {
  const ParentSurvey({
    required this.id,
    required this.institutionName,
    required this.title,
    required this.open,
    required this.questions,
    required this.children,
    this.description,
    this.closesAt,
  });

  final String id;
  final String institutionName;
  final String title;
  final String? description;
  final bool open;
  final DateTime? closesAt;
  final List<SurveyQuestion> questions;
  final List<SurveyChild> children;

  bool get needsAnswer => open && children.any((c) => !c.answered);

  factory ParentSurvey.fromJson(Map<String, dynamic> j) => ParentSurvey(
        id: j['id'] as String,
        institutionName: j['institutionName'] as String? ?? '',
        title: j['title'] as String,
        description: j['description'] as String?,
        open: j['status'] == 'OPEN',
        closesAt: _t(j['closesAt']),
        questions: (j['questions'] as List).map((e) => SurveyQuestion.fromJson(e as Map<String, dynamic>)).toList(),
        children: (j['children'] as List? ?? const [])
            .map((e) => SurveyChild(studentId: (e as Map)['studentId'] as String, name: e['name'] as String, answered: e['answered'] as bool? ?? false))
            .toList(),
      );
}

/// NTC-011
class AlbumItem {
  const AlbumItem({required this.file});
  final FileAttachment file;
  bool get isVideo => file.mime.startsWith('video/');
}

class Album {
  const Album({required this.id, required this.institutionName, required this.title, required this.authorName, required this.createdAt, required this.itemCount, required this.items, this.description});

  final String id;
  final String institutionName;
  final String title;
  final String? description;
  final String authorName;
  final DateTime createdAt;
  final int itemCount;
  final List<AlbumItem> items;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'] as String,
        institutionName: j['institutionName'] as String? ?? '',
        title: j['title'] as String,
        description: j['description'] as String?,
        authorName: (j['author'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        createdAt: _t(j['createdAt'])!,
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
        items: (j['items'] as List? ?? const []).map((e) => AlbumItem(file: FileAttachment.fromJson(e as Map<String, dynamic>))).toList(),
      );
}
