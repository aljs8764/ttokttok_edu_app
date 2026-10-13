import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';

// DASH-018~023 교사 대시보드 (앱): 홈 상단 요약 카드 + '오늘 할 일' 화면.
// API: GET /dashboard/teacher, POST /staff-memos/{id}/ack, POST /staff-attendance/check-in|check-out

typedef Json = Map<String, dynamic>;

class TeacherToday {
  TeacherToday(this.raw);
  final Json raw;

  List<Json> _list(String k) => (raw[k] as List<dynamic>? ?? const []).cast<Json>();
  List<Json> get classes => _list('classes');
  List<Json> get notArrived => _list('notArrived');
  List<Json> get notCheckedOut => _list('notCheckedOut');
  List<Json> get absenceRequests => _list('absenceRequests');
  List<Json> get cautions => _list('cautions');
  List<Json> get conversations => _list('conversations');
  List<Json> get notices => _list('notices');
  List<Json> get events => _list('events');
  List<Json> get consults => _list('consults');
  List<Json> get progressMissing => _list('progressMissing');
  List<Json> get memos => _list('memos');
  Json get work => raw['work'] as Json? ?? const {};

  int get attendanceTodo => notArrived.length + notCheckedOut.length + absenceRequests.length;
  int get commTodo => conversations.length + notices.length + events.length + consults.length;
  int get unreadMemos => memos.where((m) => m['readAt'] == null).length;
}

final teacherTodayProvider = FutureProvider.autoDispose<TeacherToday>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.institutionId));
  try {
    final r = await ref.watch(apiClientProvider).dio.get<Json>('dashboard/teacher');
    return TeacherToday(r.data!);
  } catch (e) {
    throw ApiException.from(e);
  }
});

DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
String _hm(Object? v) => _ts(v) == null ? '-' : DateFormat('HH:mm').format(_ts(v)!);

/// 홈(담당 반 목록) 맨 위 요약 카드 — 누르면 '오늘 할 일'
class TodaySummaryCard extends ConsumerWidget {
  const TodaySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(teacherTodayProvider);
    return q.when(
      loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
      data: (d) {
        final items = <(IconData, String, int, Color)>[
          (Icons.how_to_reg_outlined, tr('출결 할 일'), d.attendanceTodo, AppColors.error),
          (Icons.health_and_safety_outlined, tr('주의 원생'), d.cautions.length, AppColors.warning),
          (Icons.forum_outlined, tr('소통 할 일'), d.commTodo, AppColors.info),
          (Icons.campaign_outlined, tr('새 공지'), d.unreadMemos, AppColors.highlight),
        ];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/today'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(tr('오늘 할 일'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (icon, label, n, color) in items)
                      Expanded(
                        child: Column(children: [
                          Icon(icon, size: 20, color: n > 0 ? color : AppColors.muted),
                          const SizedBox(height: 2),
                          Text('$n', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: n > 0 ? color : AppColors.textSecondary)),
                          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
                        ]),
                      ),
                  ],
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// '오늘 할 일' 화면 — 출결·주의·소통·진도·근무·받은 공지
class TeacherTodayScreen extends ConsumerStatefulWidget {
  const TeacherTodayScreen({super.key});

  @override
  ConsumerState<TeacherTodayScreen> createState() => _TeacherTodayScreenState();
}

class _TeacherTodayScreenState extends ConsumerState<TeacherTodayScreen> {
  bool _busy = false;

  Future<void> _post(String path, [Object? data]) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).dio.post<dynamic>(path, data: data);
      ref.invalidate(teacherTodayProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(teacherTodayProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('오늘 할 일'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(teacherTodayProvider.future),
        child: q.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e), textAlign: TextAlign.center)),
            Center(child: TextButton(onPressed: () => ref.invalidate(teacherTodayProvider), child: Text(tr('다시 시도')))),
          ]),
          data: (d) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section(tr('오늘 내 수업'), d.classes.isEmpty ? [_empty(tr('오늘 수업 없음'))] : d.classes.map(_classTile).toList()),
              _section(tr('출결 할 일'), d.attendanceTodo == 0 ? [_empty(tr('처리할 출결이 없습니다'))] : [
                ...d.notArrived.map((s) => _studentTile(s, tr('미등원 · 수업 시작 {0}분 경과', [s['minutes']]), AppColors.error)),
                ...d.notCheckedOut.map((s) => _studentTile(s, tr('수업 끝나고 {0}분 · 하원 처리 안 됨', [s['minutes']]), AppColors.warning)),
                ...d.absenceRequests.map((r) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.event_busy_outlined),
                      title: Text('${r['studentName']} · ${tr(_absKind(r['kind']))}${r['expectedTime'] != null ? ' ${r['expectedTime']}' : ''}'),
                      subtitle: r['reason'] != null ? Text('${r['reason']}') : null,
                      trailing: Text(tr('확인 대기'), style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                      onTap: () => context.push('/absence'),
                    )),
              ]),
              _section(tr('오늘 원생 주의 정보'), d.cautions.isEmpty ? [_empty(tr('오늘 특별히 챙길 원생이 없습니다'))] : d.cautions.map(_cautionTile).toList()),
              _section(tr('소통 할 일'), d.commTodo == 0 ? [_empty(tr('답장·재발송할 것이 없습니다'))] : [
                ...d.consults.map((c) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.support_agent),
                      title: Text(tr('{0} 상담 · {1}', [_hm(c['startsAt']), c['studentName'] ?? '-'])),
                      subtitle: c['topic'] != null ? Text('${c['topic']}') : null,
                      onTap: () => context.push('/consults'),
                    )),
                ...d.conversations.map((c) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(tr('{0} 보호자', [c['studentName']])),
                      subtitle: c['preview'] != null ? Text('${c['preview']}', maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                      trailing: _badge('${c['unread']}', AppColors.warning),
                      onTap: () => context.push('/chat/${c['conversationId']}?title=${Uri.encodeComponent(tr('{0} 보호자', [c['studentName']]))}&staff=true'),
                    )),
                ...d.notices.map((n) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined),
                      title: Text('${n['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(tr('안 읽음 {0}명', [n['unread']])),
                      onTap: () => context.push('/notices/${n['noticeId']}'),
                    )),
                ...d.events.map((e) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.event_outlined),
                      title: Text('${e['title']}'),
                      subtitle: Text(tr('응답 마감 {0}', [DateFormat('M/d HH:mm').format(_ts(e['deadline'])!)])),
                      trailing: _badge(tr('미응답 {0}', [e['noResponse']]), AppColors.warning),
                      onTap: () => context.push('/events/${e['eventId']}'),
                    )),
              ]),
              if (d.progressMissing.isNotEmpty)
                _section(tr('진도 기록'), [
                  ...d.progressMissing.map((p) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text('${p['classroomName']}'),
                        subtitle: Text(tr('{0} 수업 끝 · 진도 미기록', [p['endTime']])),
                      )),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(tr('진도는 관리자 웹의 반 관리 > 교재·진도에서 기록합니다.'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                ]),
              _workSection(d),
              _section(tr('받은 교직원 공지'), d.memos.isEmpty ? [_empty(tr('받은 공지가 없습니다'))] : d.memos.map(_memoTile).toList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ...children,
          const SizedBox(height: 4),
        ]),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _classTile(Json c) {
    final phase = c['phase'] as String;
    final (label, color) = switch (phase) {
      'NOW' => (tr('수업 중'), AppColors.highlight),
      'UPCOMING' => (tr('예정'), AppColors.info),
      _ => (tr('끝남'), AppColors.muted),
    };
    return ListTile(
      dense: true,
      title: Text('${c['name']}  ${c['startTime']}~${c['endTime']}'),
      subtitle: Text(tr('등원 {0} / 예정 {1} · 하원 {2} · 결석 {3}', [c['present'], c['scheduled'], c['checkedOut'], c['absent']])),
      trailing: _badge(label, color),
      onTap: () => context.push('/class/${c['classroomId']}?name=${Uri.encodeQueryComponent('${c['name']}')}'),
    );
  }

  Widget _studentTile(Json s, String sub, Color color) => ListTile(
        dense: true,
        leading: Icon(Icons.person_outline, color: color),
        title: Text('${s['studentName']} · ${s['classroomName']}'),
        subtitle: Text(sub),
        trailing: s['guardianPhone'] == null
            ? null
            : IconButton(
                tooltip: tr('보호자에게 전화'),
                icon: const Icon(Icons.call_outlined),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${s['guardianPhone']}'.replaceAll('-', ''))),
              ),
        onTap: () => context.push('/class/${s['classroomId']}?name=${Uri.encodeQueryComponent('${s['classroomName']}')}'),
      );

  Widget _cautionTile(Json c) {
    final kind = c['kind'] as String;
    final text = c['text'] as String?;
    final sub = c['sub'] as String?;
    final (icon, color, line) = switch (kind) {
      'HEALTH' => (
          Icons.medical_information_outlined,
          AppColors.error,
          [if (text != null) tr('알레르기: {0}', [text]), if (sub != null) tr('지병·복용 약: {0}', [sub])].join(' · '),
        ),
      'BIRTHDAY' => (Icons.cake_outlined, AppColors.highlight, tr('오늘 생일 (만 {0}세)', [text ?? ''])),
      'ABSENCE_NOTE' => (
          Icons.event_note_outlined,
          AppColors.warning,
          [tr('학부모 신청: {0}', [tr(_absKind((sub ?? '').split(' ').first))]), if ((sub ?? '').contains(' ')) sub!.split(' ').last, if (text != null) text].join(' · '),
        ),
      _ => (Icons.psychology_alt_outlined, AppColors.info, tr('최근 상담 {0}: {1}', [sub ?? '', text ?? ''])),
    };
    return ListTile(dense: true, leading: Icon(icon, color: color), title: Text('${c['studentName']} · ${c['classroomName']}'), subtitle: Text(line));
  }

  Widget _workSection(TeacherToday d) {
    final w = d.work;
    final checkIn = w['checkInAt'], checkOut = w['checkOutAt'];
    final minutes = (w['weekMinutes'] as num? ?? 0).toInt();
    return _section(tr('내 근무'), [
      ListTile(
        dense: true,
        leading: const Icon(Icons.badge_outlined),
        title: Text(checkIn == null ? tr('아직 출근 전입니다') : tr('출근 {0} · 퇴근 {1}', [_hm(checkIn), checkOut == null ? '-' : _hm(checkOut)])),
        subtitle: Text(tr('이번 주 근무 {0}', ['${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}'])),
        trailing: checkIn == null
            ? FilledButton(onPressed: _busy ? null : () => _post('staff-attendance/check-in'), child: Text(tr('출근')))
            : checkOut == null
                ? OutlinedButton(onPressed: _busy ? null : () => _post('staff-attendance/check-out'), child: Text(tr('퇴근')))
                : null,
      ),
      if (w['runningTripId'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.directions_bus, color: AppColors.success),
          title: Text(tr('셔틀 운행 중: {0}', [w['runningRouteName'] ?? ''])),
          onTap: () => context.push('/shuttle-drive'),
        )
      else if (w['hasShuttleRoutes'] == true)
        ListTile(
          dense: true,
          leading: const Icon(Icons.directions_bus_outlined),
          title: Text(tr('셔틀 운행')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/shuttle-drive'),
        ),
    ]);
  }

  Widget _memoTile(Json m) {
    final unread = m['readAt'] == null;
    final due = m['dueDate'] as String?;
    return ListTile(
      dense: true,
      leading: Icon(Icons.campaign_outlined, color: unread ? AppColors.highlight : AppColors.muted),
      title: Text('${m['title']}', style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
      subtitle: Text([
        if (m['body'] != null) '${m['body']}',
        '${m['authorName']}',
        if (due != null) tr('마감 {0}', [DateFormat(tr('M월 d일'), dateLocale()).format(DateTime.parse(due))]),
      ].join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: TextButton(onPressed: _busy ? null : () => _post('staff-memos/${m['id']}/ack', {'done': true}), child: Text(tr('완료'))),
      onTap: unread && !_busy ? () => _post('staff-memos/${m['id']}/ack') : null,
    );
  }
}

String _absKind(Object? k) => switch (k) { 'LATE' => '지각', 'EARLY_LEAVE' => '조퇴', _ => '결석' };
