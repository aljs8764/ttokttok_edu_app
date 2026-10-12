import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/attachment_tile.dart';
import '../comm/comm_repository.dart';
import 'models.dart';
import 'parent_providers.dart';
import 'parent_repository.dart';
import '../../core/i18n/i18n.dart';

/// 알림장 상세. 화면에 처음 들어오면 열람 처리(POST /me/notices/{id}/read) — 원장님 화면의 수신 확인에 반영된다.
final _noticeDetailProvider = FutureProvider.autoDispose.family<ParentNotice, String>((ref, id) async {
  final repo = ref.watch(parentRepositoryProvider);
  final n = await repo.notice(id);
  if (n.unread) {
    // 열람 기록 실패는 화면을 막지 않는다 (다음에 들어올 때 다시 시도)
    try {
      await repo.markNoticeRead(id);
      ref.read(noticesProvider.notifier).markRead(id);
    } catch (_) {}
  }
  return n;
});

class NoticeDetailScreen extends ConsumerWidget {
  const NoticeDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(_noticeDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(tr('알림장'))),
      body: notice.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorMessage(e)),
            TextButton(onPressed: () => ref.invalidate(_noticeDetailProvider(id)), child: Text(tr('다시 시도'))),
          ]),
        ),
        data: (n) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (n.isAnnouncement)
              Text(tr('공지'), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            Text(n.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '${n.institutionName} · ${n.authorName}${n.sentAt != null ? ' · ${DateFormat(tr('M월 d일 HH:mm'), dateLocale()).format(n.sentAt!)}' : ''}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (n.children.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tr('대상: {0}', [n.children.join(', ')]), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            const Divider(height: 32),
            SelectableText(n.body, style: const TextStyle(fontSize: 16, height: 1.6)),
            if (n.attachments.isNotEmpty) ...[
              const SizedBox(height: 24),
              for (final a in n.attachments) AttachmentTile(a),
            ],
            if (n.studentIds.isNotEmpty) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.reply),
                label: Text(tr('선생님께 회신')),
                onPressed: () async {
                  try {
                    final c = await ref.read(commRepositoryProvider).openAsParent(n.studentIds.first, noticeId: n.id);
                    if (context.mounted) context.push('/chat/${c.id}?title=${Uri.encodeComponent(n.title)}&staff=false');
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
