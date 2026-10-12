import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../parent/models.dart';
import '../parent/parent_providers.dart';
import '../../core/i18n/i18n.dart';

/// NTC-008 후반 상담 예약 (학부모: 빈 시간 고르기·내 예약 / 교사: 내 상담 목록)
/// + STU-010 상담일지·CLS-003 시간표 학부모 화면 (API 는 ③에서 만들어 둠)

DateFormat get _md => DateFormat(tr('M월 d일 (E)'), dateLocale());
final _hm = DateFormat('HH:mm');
Options get _me => Options(extra: {'noInstitution': true});

class ConsultSlot {
  const ConsultSlot({
    required this.id,
    required this.institutionId,
    required this.institutionName,
    required this.teacherName,
    required this.startsAt,
    required this.endsAt,
    required this.modeLabel,
    required this.status,
    this.location,
    this.studentName,
    this.bookedByName,
    this.topic,
    this.cancelReason,
  });

  final String id, institutionId, institutionName, teacherName, modeLabel, status;
  final DateTime startsAt, endsAt;
  final String? location, studentName, bookedByName, topic, cancelReason;

  String get timeLabel => '${_hm.format(startsAt)}~${_hm.format(endsAt)}';

  factory ConsultSlot.fromJson(Map<String, dynamic> j) => ConsultSlot(
        id: j['id'] as String,
        institutionId: j['institutionId'] as String,
        institutionName: j['institutionName'] as String? ?? '',
        teacherName: (j['teacher'] as Map<String, dynamic>)['name'] as String? ?? '',
        startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
        endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
        modeLabel: j['modeLabel'] as String? ?? '',
        status: j['status'] as String,
        location: j['location'] as String?,
        studentName: (j['student'] as Map<String, dynamic>?)?['name'] as String?,
        bookedByName: (j['bookedBy'] as Map<String, dynamic>?)?['name'] as String?,
        topic: j['topic'] as String?,
        cancelReason: j['cancelReason'] as String?,
      );
}

List<ConsultSlot> _slots(Object? data) => (data as List).map((e) => ConsultSlot.fromJson(e as Map<String, dynamic>)).toList();

final availableConsultsProvider = FutureProvider.autoDispose<List<ConsultSlot>>((ref) async {
  final child = ref.watch(selectedChildProvider);
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/consult-slots', options: _me, queryParameters: {if (child != null) 'childId': child});
  return _slots(r.data);
});

final myConsultsProvider = FutureProvider.autoDispose<List<ConsultSlot>>((ref) async {
  final child = ref.watch(selectedChildProvider);
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/consult-bookings', options: _me, queryParameters: {if (child != null) 'childId': child});
  return _slots(r.data);
});

String _statusLabel(String s) => switch (s) { 'BOOKED' => tr('예약됨'), 'DONE' => tr('상담 완료'), 'CANCELED' => tr('취소됨'), _ => tr('예약 가능') };

// ───────── 학부모: 상담 예약 ─────────
class ParentConsultScreen extends ConsumerWidget {
  const ParentConsultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('상담 예약')), bottom: TabBar(tabs: [Tab(text: tr('예약하기')), Tab(text: tr('내 예약'))])),
        body: const TabBarView(children: [_Available(), _Mine()]),
      ),
    );
  }
}

class _Available extends ConsumerWidget {
  const _Available();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(availableConsultsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(availableConsultsProvider),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e)))]),
        data: (slots) {
          if (slots.isEmpty) {
            return ListView(children: [
              Padding(padding: EdgeInsets.all(24), child: Text(tr('지금 예약할 수 있는 상담 시간이 없습니다.\n선생님이 상담 시간을 열면 여기에 보입니다.'), textAlign: TextAlign.center)),
            ]);
          }
          final days = <String, List<ConsultSlot>>{};
          for (final s in slots) {
            days.putIfAbsent(_md.format(s.startsAt), () => []).add(s);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final e in days.entries) ...[
              Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))),
              for (final s in e.value)
                Card(
                  child: ListTile(
                    title: Text(tr('{0} · {1} 선생님', [s.timeLabel, s.teacherName])),
                    subtitle: Text('${s.institutionName} · ${s.modeLabel}${s.location != null ? ' · ${s.location}' : ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _book(context, ref, s),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }

  Future<void> _book(BuildContext context, WidgetRef ref, ConsultSlot s) async {
    final children = ref.read(childrenProvider).valueOrNull ?? const <Child>[];
    final students = [
      for (final c in children)
        for (final e in c.enrollments)
          if (e.institutionId == s.institutionId) e,
    ];
    if (students.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BookSheet(slot: s, students: students),
    );
    if (ok == true) {
      ref.invalidate(availableConsultsProvider);
      ref.invalidate(myConsultsProvider);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('상담을 예약했어요. 선생님께 알림이 갔습니다.'))));
    }
  }
}

class _BookSheet extends ConsumerStatefulWidget {
  const _BookSheet({required this.slot, required this.students});
  final ConsultSlot slot;
  final List<Enrollment> students;

  @override
  ConsumerState<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends ConsumerState<_BookSheet> {
  late String _studentId = widget.students.first.studentId;
  final _topic = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>('me/consult-slots/${widget.slot.id}/book',
          options: _me, data: {'studentId': _studentId, 'topic': _topic.text.trim().isEmpty ? null : _topic.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_md.format(s.startsAt)} ${s.timeLabel}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        Text(tr('{0} 선생님 · {1}{2}', [s.teacherName, s.modeLabel, s.location != null ? ' · ${s.location}' : '']), style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        if (widget.students.length > 1)
          DropdownButtonFormField<String>(
            initialValue: _studentId,
            decoration: InputDecoration(labelText: tr('자녀')),
            items: [for (final e in widget.students) DropdownMenuItem(value: e.studentId, child: Text(e.studentName))],
            onChanged: (v) => setState(() => _studentId = v ?? _studentId),
          ),
        const SizedBox(height: 12),
        TextField(controller: _topic, maxLength: 300, maxLines: 3, decoration: InputDecoration(labelText: tr('상담하고 싶은 내용 (선택)'))),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(tr('예약하기'))),
      ]),
    );
  }
}

class _Mine extends ConsumerWidget {
  const _Mine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myConsultsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myConsultsProvider),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e)))]),
        data: (slots) => slots.isEmpty
            ? ListView(children: [Padding(padding: EdgeInsets.all(24), child: Text(tr('예약한 상담이 없습니다.'), textAlign: TextAlign.center))])
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final s in slots)
                  Card(
                    child: ListTile(
                      title: Text('${_md.format(s.startsAt)} ${s.timeLabel}'),
                      subtitle: Text([
                        '${s.teacherName} 선생님 · ${s.modeLabel}',
                        if (s.studentName != null) s.studentName!,
                        _statusLabel(s.status) + (s.cancelReason != null ? ' (${s.cancelReason})' : ''),
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: s.status == 'BOOKED' && s.startsAt.isAfter(DateTime.now())
                          ? TextButton(onPressed: () => _cancel(context, ref, s), child: Text(tr('취소')))
                          : null,
                    ),
                  ),
              ]),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, ConsultSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('예약을 취소할까요?')),
        content: Text(tr('{0} {1} {2} 선생님 상담', [_md.format(s.startsAt), s.timeLabel, s.teacherName])),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('아니요'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('취소하기')))],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>('me/consult-bookings/${s.id}/cancel', options: _me);
      ref.invalidate(myConsultsProvider);
      ref.invalidate(availableConsultsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }
}

// ───────── 교사앱: 내 상담 ─────────
final teacherConsultsProvider = FutureProvider.autoDispose<List<ConsultSlot>>((ref) async {
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('consult-slots');
  return _slots(r.data);
});

class TeacherConsultScreen extends ConsumerWidget {
  const TeacherConsultScreen({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref, ConsultSlot s, String op) async {
    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>('consult-slots/${s.id}/$op', data: op == 'cancel' ? {'reason': null} : null);
      ref.invalidate(teacherConsultsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teacherConsultsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('상담 예약'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(teacherConsultsProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e)))]),
          data: (slots) => slots.isEmpty
              ? ListView(children: [
                  Padding(padding: EdgeInsets.all(24), child: Text(tr('앞으로 2주 동안 열린 상담 시간이 없습니다.\n상담 시간은 관리자 웹 "상담 예약"에서 엽니다.'), textAlign: TextAlign.center)),
                ])
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final s in slots)
                    Card(
                      child: ListTile(
                        title: Text('${_md.format(s.startsAt)} ${s.timeLabel}'),
                        subtitle: Text(s.studentName != null
                            ? '${s.studentName} · ${s.bookedByName ?? ''}${s.topic != null ? '\n${s.topic}' : ''}'
                            : '${_statusLabel(s.status)} · ${s.modeLabel}'),
                        trailing: s.status == 'BOOKED'
                            ? PopupMenuButton<String>(
                                onSelected: (op) => _act(context, ref, s, op),
                                itemBuilder: (_) => [PopupMenuItem(value: 'done', child: Text(tr('상담 완료'))), PopupMenuItem(value: 'cancel', child: Text(tr('취소(학부모에게 알림)')))],
                              )
                            : Text(_statusLabel(s.status), style: const TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

// ───────── 학부모: 상담일지 (STU-010) ─────────
final myCounselNotesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final child = ref.watch(selectedChildProvider);
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/counsel-notes', options: _me, queryParameters: {if (child != null) 'childId': child});
  return r.data!.cast<Map<String, dynamic>>();
});

class CounselNotesScreen extends ConsumerWidget {
  const CounselNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myCounselNotesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('상담 기록'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myCounselNotesProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e)))]),
          data: (notes) => notes.isEmpty
              ? ListView(children: [Padding(padding: EdgeInsets.all(24), child: Text(tr('선생님이 공개한 상담 기록이 없습니다.'), textAlign: TextAlign.center))])
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final n in notes)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            '${_md.format(DateTime.parse(n['occurredOn'] as String))} · ${n['studentName'] ?? ''} · ${n['institutionName'] ?? ''}',
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Text(n['body'] as String? ?? '', style: const TextStyle(height: 1.4)),
                          const SizedBox(height: 6),
                          Text(tr('{0} 선생님', [(n['author'] as Map<String, dynamic>?)?['name'] ?? '']), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ]),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

// ───────── 학부모: 주간 시간표 (CLS-003) ─────────
final myTimetableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final child = ref.watch(selectedChildProvider);
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/timetable', options: _me, queryParameters: {if (child != null) 'childId': child});
  return r.data!.cast<Map<String, dynamic>>();
});

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String _hhmm(Object? v) {
  final s = (v as String?) ?? '';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myTimetableProvider);
    final today = DateTime.now().weekday;
    return Scaffold(
      appBar: AppBar(title: Text(tr('주간 시간표'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myTimetableProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e)))]),
          data: (slots) {
            if (slots.isEmpty) {
              return ListView(children: [Padding(padding: EdgeInsets.all(24), child: Text(tr('학원에서 등록한 시간표가 없습니다.'), textAlign: TextAlign.center))]);
            }
            final byDay = <int, List<Map<String, dynamic>>>{};
            for (final s in slots) {
              byDay.putIfAbsent((s['weekday'] as num).toInt(), () => []).add(s);
            }
            for (final l in byDay.values) {
              l.sort((a, b) => _hhmm(a['startTime']).compareTo(_hhmm(b['startTime'])));
            }
            final days = byDay.keys.toList()..sort();
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final d in days) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(tr('{0}요일', [tr(_weekdays[(d - 1).clamp(0, 6)])]) + (d == today ? tr(' · 오늘') : ''),
                      style: TextStyle(fontWeight: FontWeight.w700, color: d == today ? AppColors.accent : null)),
                ),
                for (final s in byDay[d]!)
                  Card(
                    child: ListTile(
                      leading: Text('${_hhmm(s['startTime'])}\n${_hhmm(s['endTime'])}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                      title: Text(s['subject'] as String? ?? s['classroomName'] as String? ?? ''),
                      subtitle: Text([
                        s['studentName'],
                        s['institutionName'],
                        s['classroomName'],
                        if (s['room'] != null) s['room'],
                        if ((s['teacher'] as Map<String, dynamic>?)?['name'] != null) tr('{0} 선생님', [(s['teacher'] as Map<String, dynamic>)['name']]),
                      ].whereType<String>().join(' · ')),
                    ),
                  ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}
