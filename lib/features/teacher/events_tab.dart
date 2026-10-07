import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/date_time_field.dart';
import '../../core/widgets/pill.dart';
import 'content_models.dart';
import 'content_providers.dart';

/// 행사 탭 (EVT-001·003) — 내가 만든 행사 (원장·실장은 기관 전체). 예정 / 지난 행사 포함 전환.
class TeacherEventsTab extends ConsumerStatefulWidget {
  const TeacherEventsTab({super.key});

  @override
  ConsumerState<TeacherEventsTab> createState() => _TeacherEventsTabState();
}

class _TeacherEventsTabState extends ConsumerState<TeacherEventsTab> {
  bool _upcoming = true;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider(_upcoming));
    return Scaffold(
      appBar: AppBar(title: const Text('행사')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/events/new'),
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('행사 만들기'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('예정')),
                ButtonSegment(value: false, label: Text('지난 행사 포함')),
              ],
              selected: {_upcoming},
              onSelectionChanged: (s) => setState(() => _upcoming = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(eventsProvider(_upcoming).future),
              child: events.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  const SizedBox(height: 120),
                  Text(errorMessage(e), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                  Center(child: TextButton(onPressed: () => ref.invalidate(eventsProvider(_upcoming)), child: const Text('다시 시도'))),
                ]),
                data: (s) {
                  if (s.items.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.event_outlined, size: 48, color: AppColors.muted),
                      const SizedBox(height: 12),
                      Center(child: Text(_upcoming ? '예정된 행사가 없습니다' : '행사가 없습니다', style: const TextStyle(color: AppColors.textSecondary))),
                    ]);
                  }
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 300) ref.read(eventsProvider(_upcoming).notifier).loadMore();
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: s.items.length + (s.loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => i >= s.items.length
                          ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                          : _EventTile(s.items[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e);
  final SchoolEvent e;

  @override
  Widget build(BuildContext context) {
    final t = e.tally;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/events/${e.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                if (e.canceled) const Pill('취소', AppColors.muted),
              ]),
              const SizedBox(height: 4),
              Text('${formatDateTime(e.startsAt)}${e.location != null && e.location!.isNotEmpty ? ' · ${e.location}' : ''}', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text('${targetSummary(e.targets)} · ${e.authorName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              if (!e.rsvpEnabled)
                const Text('참석 여부 받지 않음', style: TextStyle(fontSize: 13, color: AppColors.muted))
              else if (t != null)
                TallyLine(t),
            ],
          ),
        ),
      ),
    );
  }
}

/// "참석 12 · 불참 3 · 미응답 5" 한 줄 + 막대
class TallyLine extends StatelessWidget {
  const TallyLine(this.t, {super.key});
  final Tally t;

  @override
  Widget build(BuildContext context) {
    Widget bar(int n, Color c) => n == 0 ? const SizedBox.shrink() : Expanded(flex: n, child: Container(height: 6, color: c));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Row(children: [
          bar(t.attend, AppColors.success),
          bar(t.absent, AppColors.error),
          bar(t.pending, const Color(0xFFE6E8F0)),
          if (t.targets == 0) Expanded(child: Container(height: 6, color: const Color(0xFFE6E8F0))),
        ]),
      ),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '참석 ${t.attend}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          const TextSpan(text: '  ·  '),
          TextSpan(text: '불참 ${t.absent}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
          const TextSpan(text: '  ·  '),
          TextSpan(text: '미응답 ${t.pending}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
          TextSpan(text: '  (대상 ${t.targets}명)', style: const TextStyle(color: AppColors.textSecondary)),
        ]),
        style: const TextStyle(fontSize: 13),
      ),
    ]);
  }
}
