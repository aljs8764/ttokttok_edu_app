import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/date_time_field.dart';
import '../../core/widgets/pill.dart';
import 'content_models.dart';
import 'content_providers.dart';

/// NTC-004 알림장 탭 — 내가 보낸·예약한 알림장 (원장·실장은 기관 전체). 누르면 상세(수신 확인), + 로 작성.
class TeacherNoticesTab extends ConsumerWidget {
  const TeacherNoticesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    final filter = ref.watch(noticeFilterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('알림장')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/notices/new'),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('알림장 쓰기'),
      ),
      body: Column(children: [
        const _FilterBar(),
        Expanded(child: RefreshIndicator(
        onRefresh: () => ref.refresh(noticesProvider.future),
        child: notices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Text(errorMessage(e), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            Center(child: TextButton(onPressed: () => ref.invalidate(noticesProvider), child: const Text('다시 시도'))),
          ]),
          data: (s) {
            if (s.items.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                const Icon(Icons.menu_book_outlined, size: 48, color: AppColors.muted),
                const SizedBox(height: 12),
                Center(child: Text(filter.isEmpty ? '보낸 알림장이 없습니다' : '조건에 맞는 알림장이 없습니다', style: const TextStyle(color: AppColors.textSecondary))),
              ]);
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 300) ref.read(noticesProvider.notifier).loadMore();
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: s.items.length + (s.loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => i >= s.items.length
                    ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                    : _NoticeTile(s.items[i]),
              ),
            );
          },
        ),
        )),
      ]),
    );
  }
}

/// 종류·상태 필터 칩. 같은 칩을 다시 누르면 해제.
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(noticeFilterProvider);
    final c = ref.read(noticeFilterProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        for (final k in NoticeKind.values) ...[
          FilterChip(label: Text(k.label), selected: f.kind == k, onSelected: (on) => c.setKind(on ? k : null)),
          const SizedBox(width: 6),
        ],
        const SizedBox(width: 6),
        for (final s in NoticeStatus.values) ...[
          FilterChip(label: Text(s.label), selected: f.status == s, onSelected: (on) => c.setStatus(on ? s : null)),
          const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile(this.n);
  final TeacherNotice n;

  @override
  Widget build(BuildContext context) {
    final stats = n.readStats;
    final when = n.when;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/notices/${n.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Pill(n.kind.label, n.kind == NoticeKind.announcement ? AppColors.accent : AppColors.primary),
                const SizedBox(width: 6),
                Pill(n.status.label, n.status.color),
                if (n.pinned) ...[const SizedBox(width: 6), const Icon(Icons.push_pin, size: 14, color: AppColors.muted)],
                const Spacer(),
                if (when != null) Text(formatDateTime(when), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 8),
              Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text('${targetSummary(n.targets)} · ${n.authorName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                if (n.status == NoticeStatus.sent && stats != null)
                  Text('열람 ${stats.readStudents}/${stats.targetStudents}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
