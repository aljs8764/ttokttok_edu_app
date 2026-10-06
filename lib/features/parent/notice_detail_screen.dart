import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'models.dart';
import 'parent_providers.dart';
import 'parent_repository.dart';

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
      appBar: AppBar(title: const Text('알림장')),
      body: notice.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorMessage(e)),
            TextButton(onPressed: () => ref.invalidate(_noticeDetailProvider(id)), child: const Text('다시 시도')),
          ]),
        ),
        data: (n) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (n.isAnnouncement)
              const Text('공지', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            Text(n.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '${n.institutionName} · ${n.authorName}${n.sentAt != null ? ' · ${DateFormat('M월 d일 HH:mm', 'ko_KR').format(n.sentAt!)}' : ''}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (n.children.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('대상: ${n.children.join(', ')}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            const Divider(height: 32),
            SelectableText(n.body, style: const TextStyle(fontSize: 16, height: 1.6)),
            if (n.attachments.isNotEmpty) ...[
              const SizedBox(height: 24),
              for (final a in n.attachments) _Attachment(a),
            ],
          ],
        ),
      ),
    );
  }
}

/// 이미지는 바로 보여 주고, PDF 등은 링크 복사 (외부 앱 열기는 url_launcher 추가 시)
class _Attachment extends StatelessWidget {
  const _Attachment(this.a);
  final FileAttachment a;

  @override
  Widget build(BuildContext context) {
    final url = a.downloadUrl;
    if (a.isImage && url != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fileRow(context, url),
            loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          ),
        ),
      );
    }
    return _fileRow(context, url);
  }

  Widget _fileRow(BuildContext context, String? url) => Card(
        child: ListTile(
          leading: const Icon(Icons.attach_file),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_size(a.size)),
          trailing: url == null ? null : const Icon(Icons.copy, size: 18),
          onTap: url == null
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('파일 링크를 복사했습니다 (5분 동안 열 수 있어요)')));
                },
        ),
      );

  static String _size(int n) => n < 1024 * 1024 ? '${(n / 1024).ceil()}KB' : '${(n / 1024 / 1024).toStringAsFixed(1)}MB';
}
