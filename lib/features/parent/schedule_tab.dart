import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'models.dart';
import 'parent_providers.dart';
import 'rsvp_sheet.dart';

/// PAR-005 행사(응답 필요 먼저) + PAR-003 주간 스케줄(수업·행사, 자녀별)
class ScheduleTab extends ConsumerWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    final week = ref.watch(scheduleProvider);
    final offset = ref.watch(weekOffsetProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventsProvider);
        ref.invalidate(scheduleProvider);
        await ref.read(scheduleProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _SectionTitle('다가오는 행사'),
          events.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(errorMessage(e)),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('예정된 행사가 없습니다', style: TextStyle(color: AppColors.textSecondary)),
                  )
                : Column(children: [for (final e in list) _EventCard(e)]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: _SectionTitle('이번 주 일정')),
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => ref.read(weekOffsetProvider.notifier).state--),
            TextButton(
              onPressed: offset == 0 ? null : () => ref.read(weekOffsetProvider.notifier).state = 0,
              child: Text(offset == 0 ? '이번 주' : offset > 0 ? '$offset주 뒤' : '${-offset}주 전'),
            ),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => ref.read(weekOffsetProvider.notifier).state++),
          ]),
          week.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(errorMessage(e)),
            data: (w) => _WeekView(w),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}

class _EventCard extends ConsumerWidget {
  const _EventCard(this.e);
  final ParentEvent e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('M월 d일 (E) HH:mm', 'ko_KR');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: e.needsAnswer
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.accent, width: 1.5))
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showRsvpSheet(context, e),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      e.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        decoration: e.canceled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (e.canceled)
                    const Text('취소됨', style: TextStyle(color: AppColors.error))
                  else if (e.needsAnswer)
                    const Text('응답 필요', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                Text('${df.format(e.startsAt)}${e.location != null ? ' · ${e.location}' : ''}', style: const TextStyle(color: AppColors.textSecondary)),
                Text(e.institutionName, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                if (e.rsvpEnabled) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final c in e.children) RsvpChip(c)]),
                  if (e.rsvpDeadline != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        e.open ? '응답 마감 ${DateFormat('M/d HH:mm').format(e.rsvpDeadline!)}' : '응답이 마감되었습니다',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView(this.w);
  final WeekSchedule w;

  @override
  Widget build(BuildContext context) {
    if (w.children.isEmpty) {
      return const Text('연결된 자녀가 없습니다', style: TextStyle(color: AppColors.textSecondary));
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final multi = w.children.length > 1;
    // 날짜별로 모든 자녀의 일정을 모은다
    final byDay = <DateTime, List<(String, ScheduleItem)>>{};
    for (final c in w.children) {
      for (final d in c.days) {
        byDay.putIfAbsent(DateUtils.dateOnly(d.date), () => []).addAll(d.items.map((i) => (c.name, i)));
      }
    }
    final days = List.generate(7, (i) => DateUtils.dateOnly(w.weekStart.add(Duration(days: i))));

    return Card(
      child: Column(
        children: [
          for (final d in days)
            Container(
              decoration: BoxDecoration(
                color: d == today ? AppColors.primary.withValues(alpha: 0.04) : null,
                border: const Border(bottom: BorderSide(color: Color(0xFFEFF0F5))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      DateFormat('E d', 'ko_KR').format(d),
                      style: TextStyle(fontWeight: d == today ? FontWeight.w800 : FontWeight.w500, color: d == today ? AppColors.accent : null),
                    ),
                  ),
                  Expanded(
                    child: (byDay[d] ?? const []).isEmpty
                        ? const Text('-', style: TextStyle(color: AppColors.muted))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (name, it) in byDay[d]!)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(children: [
                                    Icon(it.kind == 'EVENT' ? Icons.celebration_outlined : Icons.class_outlined, size: 16, color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${ScheduleItem.hm(it.startsAt)}${it.endsAt != null ? '~${ScheduleItem.hm(it.endsAt)}' : ''} '
                                        '${it.title}${multi ? ' · $name' : ''}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ]),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
