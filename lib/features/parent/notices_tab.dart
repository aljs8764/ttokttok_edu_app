import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'models.dart';
import 'parent_providers.dart';

/// PAR-004 알림장함 — 고정 공지가 위, 안 읽은 건 굵게·점 표시. 누르면 상세(= 열람 처리).
class NoticesTab extends ConsumerWidget {
  const NoticesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(noticesProvider.notifier).refresh(),
      child: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [const SizedBox(height: 100), Center(child: Text(errorMessage(e)))]),
        data: (s) {
          if (s.items.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 100),
              Icon(Icons.mail_outline, size: 48, color: AppColors.muted),
              SizedBox(height: 12),
              Center(child: Text('받은 알림장이 없습니다', style: TextStyle(color: AppColors.textSecondary))),
            ]);
          }
          final pinned = s.items.where((n) => n.pinned).toList();
          final rest = s.items.where((n) => !n.pinned).toList();
          final list = [...pinned, ...rest];
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 300) ref.read(noticesProvider.notifier).loadMore();
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => NoticeTile(list[i]),
            ),
          );
        },
      ),
    );
  }
}

class NoticeTile extends StatelessWidget {
  const NoticeTile(this.n, {super.key});
  final ParentNotice n;

  @override
  Widget build(BuildContext context) {
    final when = n.sentAt == null ? '' : _relative(n.sentAt!);
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
                if (n.pinned) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin, size: 16, color: AppColors.accent)),
                if (n.isAnnouncement) const _Tag('공지', AppColors.primary),
                Expanded(
                  child: Text(
                    n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: n.unread ? FontWeight.w800 : FontWeight.w500),
                  ),
                ),
                if (n.unread) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.circle, size: 8, color: AppColors.accent)),
              ]),
              const SizedBox(height: 4),
              Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text(
                '${n.institutionName} · ${n.authorName} · $when${n.attachments.isNotEmpty ? ' · 📎${n.attachments.length}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24 && DateUtils.isSameDay(t, DateTime.now())) return DateFormat('HH:mm').format(t);
    return DateFormat('M/d HH:mm').format(t);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );
}
