import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/date_time_field.dart';
import '../../core/widgets/pill.dart';
import 'content_models.dart';
import 'content_providers.dart';
import 'content_repository.dart';
import 'events_tab.dart' show TallyLine;

const _remindCooldown = Duration(minutes: 30);

enum _Filter { pending, attend, absent, all }

/// EVT-003 응답 집계·명단(미응답 먼저), EVT-004 수동 독촉(30분 간격), 행사 수정·취소.
/// 명단 엑셀은 관리자 웹에서. 응답이 들어오는 건 당겨서 새로고침으로 확인한다.
class TeacherEventDetailScreen extends ConsumerStatefulWidget {
  const TeacherEventDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<TeacherEventDetailScreen> createState() => _TeacherEventDetailScreenState();
}

class _TeacherEventDetailScreenState extends ConsumerState<TeacherEventDetailScreen> {
  _Filter _filter = _Filter.pending;
  bool _busy = false;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _remind() async {
    setState(() => _busy = true);
    try {
      final n = await ref.read(contentRepositoryProvider).remindEvent(widget.id);
      invalidateEvents(ref, id: widget.id);
      _toast('미응답 보호자 $n명께 독촉 알림을 보냈습니다');
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('행사를 취소할까요?'),
        content: const Text('학부모 앱에서 취소된 행사로 표시됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('행사 취소')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(contentRepositoryProvider).cancelEvent(widget.id);
      invalidateEvents(ref, id: widget.id);
      _toast('행사를 취소했습니다');
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(eventSummaryProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('행사')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorMessage(e)),
            TextButton(onPressed: () => ref.invalidate(eventSummaryProvider(widget.id)), child: const Text('다시 시도')),
          ]),
        ),
        data: (s) {
          final e = s.event;
          final rows = switch (_filter) {
            _Filter.pending => s.rows.where((r) => r.answer == null).toList(),
            _Filter.attend => s.rows.where((r) => r.answer == RsvpAnswer.attend).toList(),
            _Filter.absent => s.rows.where((r) => r.answer == RsvpAnswer.absent).toList(),
            _Filter.all => s.rows,
          };
          final nextRemind = e.remindedAt?.add(_remindCooldown);
          final cooling = nextRemind != null && nextRemind.isAfter(DateTime.now());
          final remindable = e.rsvpEnabled && !e.canceled && !e.deadlinePassed && s.tally.pending > 0 && !cooling;

          return RefreshIndicator(
            onRefresh: () async {
              invalidateEvents(ref, id: widget.id);
              await ref.read(eventSummaryProvider(widget.id).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(child: Text(e.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  if (e.canceled) const Pill('취소', AppColors.muted),
                ]),
                const SizedBox(height: 8),
                _info(Icons.schedule, '${formatDateTime(e.startsAt)}${e.endsAt != null ? ' ~ ${formatDateTime(e.endsAt!)}' : ''}'),
                if (e.location != null && e.location!.isNotEmpty) _info(Icons.place_outlined, e.location!),
                _info(Icons.groups_outlined, '${e.targets.map((t) => t.name ?? '').join(', ')} · ${e.authorName}'),
                if (e.rsvpEnabled && e.rsvpDeadline != null) _info(Icons.how_to_reg_outlined, '응답 마감 ${formatDateTime(e.rsvpDeadline!)}${e.deadlinePassed ? ' (마감됨)' : ''}'),
                if (e.body != null && e.body!.isNotEmpty) ...[
                  const Divider(height: 28),
                  SelectableText(e.body!, style: const TextStyle(fontSize: 15, height: 1.6)),
                ],
                if (!e.canceled) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: _busy ? null : () => context.push('/events/${e.id}/edit'), child: const Text('수정'))),
                    const SizedBox(width: 12),
                    Expanded(child: OutlinedButton(onPressed: _busy ? null : _cancel, child: const Text('행사 취소'))),
                  ]),
                ],
                const Divider(height: 32),
                if (!e.rsvpEnabled)
                  const Text('이 행사는 참석 여부를 받지 않습니다.', style: TextStyle(color: AppColors.textSecondary))
                else ...[
                  const Text('참석 현황', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TallyLine(s.tally),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy || !remindable ? null : _remind,
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: const Text('안 답한 분께 독촉'),
                  ),
                  if (cooling) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${formatDateTime(nextRemind!)} 이후에 다시 독촉할 수 있습니다', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    for (final f in _Filter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.pending => '미응답 ${s.tally.pending}',
                          _Filter.attend => '참석 ${s.tally.attend}',
                          _Filter.absent => '불참 ${s.tally.absent}',
                          _Filter.all => '전체 ${s.rows.length}',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('해당하는 원생이 없습니다', style: TextStyle(color: AppColors.textSecondary))))
                  else
                    for (final r in rows) _row(r),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary))),
        ]),
      );

  Widget _row(RsvpRow r) {
    final a = r.answer;
    final sub = [
      if (r.classroomNames.isNotEmpty) r.classroomNames.join(', '),
      if (r.reason != null && r.reason!.isNotEmpty) '사유: ${r.reason}',
      if (r.respondedAt != null) '${formatDateTime(r.respondedAt!)}${r.respondedByName != null ? ' ${r.respondedByName}' : ''}',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(r.studentName),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: a == null ? const Pill('미응답', AppColors.warning) : Pill(a.label, a.color),
    );
  }
}
