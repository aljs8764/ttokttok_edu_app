import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/widgets/attachment_tile.dart';
import '../../core/widgets/date_time_field.dart';
import '../../core/widgets/pill.dart';
import 'content_models.dart';
import 'content_providers.dart';
import 'content_repository.dart';
import '../../core/i18n/i18n.dart';

/// NTC-004·005·006 알림장 상세 — 발송 내용, 수신 확인(읽음/안 읽음 명단), 안 읽은 분께 다시 보내기(30분 간격).
/// 예약 건은 수정·취소. 수정·취소·재발송은 작성자 본인 또는 원장·실장.
class TeacherNoticeDetailScreen extends ConsumerStatefulWidget {
  const TeacherNoticeDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<TeacherNoticeDetailScreen> createState() => _TeacherNoticeDetailScreenState();
}

class _TeacherNoticeDetailScreenState extends ConsumerState<TeacherNoticeDetailScreen> {
  bool _showReceipts = false;
  bool _busy = false;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('예약을 취소할까요?')),
        content: Text(tr('취소하면 발송되지 않습니다.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('아니오'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('예약 취소'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(contentRepositoryProvider).cancelNotice(widget.id);
      invalidateNotices(ref, id: widget.id);
      _toast(tr('예약을 취소했습니다'));
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('안 읽은 분께 다시 보낼까요?')),
        content: Text(tr('아직 열람하지 않은 학부모께만 푸시를 다시 보냅니다. 다시 보내기는 30분에 한 번만 됩니다.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('아니오'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('다시 보내기'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(contentRepositoryProvider).resendUnread(widget.id);
      invalidateNotices(ref, id: widget.id);
      _toast(tr('안 읽은 원생 {0}명의 보호자 {1}명께 다시 보냈습니다', [r.students, r.pushRecipients]));
    } catch (e) {
      _toast(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(noticeDetailProvider(widget.id));
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('알림장'))),
      body: notice.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorMessage(e)),
            TextButton(onPressed: () => ref.invalidate(noticeDetailProvider(widget.id)), child: Text(tr('다시 시도'))),
          ]),
        ),
        data: (n) {
          final canManage = (auth.membership?.role.isManager ?? false) || n.authorId == auth.user?.id;
          return RefreshIndicator(
            onRefresh: () async {
              invalidateNotices(ref, id: widget.id);
              await ref.read(noticeDetailProvider(widget.id).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Pill(n.kind.label, n.kind == NoticeKind.announcement ? AppColors.accent : AppColors.primary),
                  const SizedBox(width: 6),
                  Pill(n.status.label, n.status.color),
                  if (n.pinned) ...[const SizedBox(width: 6), const Icon(Icons.push_pin, size: 14, color: AppColors.muted)],
                ]),
                const SizedBox(height: 10),
                Text(n.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${n.authorName} · ${_whenLabel(n)}', style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(tr('받는 사람: {0}', [n.targets.map((t) => t.name ?? '').join(', ')]), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const Divider(height: 32),
                SelectableText(n.body, style: const TextStyle(fontSize: 16, height: 1.6)),
                if (n.attachments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  for (final a in n.attachments) AttachmentTile(a),
                ],
                if (n.status == NoticeStatus.scheduled && canManage) ...[
                  const Divider(height: 32),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: _busy ? null : () => context.push('/notices/${n.id}/edit'), child: Text(tr('수정')))),
                    const SizedBox(width: 12),
                    Expanded(child: OutlinedButton(onPressed: _busy ? null : _cancel, child: Text(tr('예약 취소')))),
                  ]),
                ],
                if (n.status == NoticeStatus.sent) ...[
                  const Divider(height: 32),
                  _Readers(
                    id: n.id,
                    stats: n.readStats,
                    open: _showReceipts,
                    canResend: canManage,
                    busy: _busy,
                    onToggle: () => setState(() => _showReceipts = !_showReceipts),
                    onResend: _resend,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

String _whenLabel(TeacherNotice n) => switch (n.status) {
      NoticeStatus.sent => n.sentAt != null ? tr('{0} 발송', [formatDateTime(n.sentAt!)]) : tr('발송'),
      NoticeStatus.scheduled => n.scheduledAt != null ? tr('{0} 예약', [formatDateTime(n.scheduledAt!)]) : tr('예약'),
      NoticeStatus.canceled => tr('예약 취소됨'),
    };

/// 열람 현황 막대 + 수신 확인 명단
class _Readers extends ConsumerWidget {
  const _Readers({required this.id, required this.stats, required this.open, required this.canResend, required this.busy, required this.onToggle, required this.onResend});

  final String id;
  final ReadStats? stats;
  final bool open;
  final bool canResend;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final receipts = open ? ref.watch(noticeReceiptsProvider(id)) : null;
    // 명단을 열었으면 명단의 집계(재발송 직후 값)를 우선
    final shown = receipts?.valueOrNull?.stats ?? s;
    final canResendAt = receipts?.valueOrNull?.canResendAt;
    final cooling = canResendAt != null && canResendAt.isAfter(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('수신 확인'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (shown == null || shown.targetStudents == 0)
          Text(tr('받는 원생이 없습니다'), style: TextStyle(color: AppColors.textSecondary))
        else ...[
          LinearProgressIndicator(value: (shown.rate ?? 0).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 6),
          Text(tr('{0}/{1}명 열람 ({2}%)', [shown.readStudents, shown.targetStudents, ((shown.rate ?? 0) * 100).round()]), style: const TextStyle(color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: onToggle, child: Text(open ? tr('명단 접기') : tr('누가 읽었나요')))),
          if (canResend) ...[
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy || cooling || (shown != null && shown.unread <= 0) ? null : onResend,
                child: Text(tr('안 읽은 분께 다시')),
              ),
            ),
          ],
        ]),
        if (cooling) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('{0} 이후에 다시 보낼 수 있습니다', [formatDateTime(canResendAt!)]), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        if (receipts != null)
          receipts.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.only(top: 12), child: Text(errorMessage(e), style: const TextStyle(color: AppColors.error))),
            data: (r) {
              final unread = r.students.where((x) => !x.read).toList();
              final read = r.students.where((x) => x.read).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 12),
                if (unread.isNotEmpty) ...[
                  Text(tr('안 읽음 {0}명', [unread.length]), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning)),
                  for (final x in unread) _row(x),
                  const SizedBox(height: 12),
                ],
                if (read.isNotEmpty) ...[
                  Text(tr('읽음 {0}명', [read.length]), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
                  for (final x in read) _row(x),
                ],
              ]);
            },
          ),
      ],
    );
  }

  Widget _row(ReceiptStudent x) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(x.studentName),
        subtitle: Text([
          if (x.classroomNames.isNotEmpty) x.classroomNames.join(', '),
          if (!x.appLinked) tr('앱 미연결'),
          if (x.read && x.firstReadAt != null) tr('{0} 열람', [formatDateTime(x.firstReadAt!)]),
          if (!x.read && x.resentCount > 0) tr('재발송 {0}회', [x.resentCount]),
        ].join(' · ')),
        trailing: Icon(x.read ? Icons.done_all : Icons.mark_email_unread_outlined, size: 18, color: x.read ? AppColors.success : AppColors.warning),
      );
}
