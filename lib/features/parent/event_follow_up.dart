import '../../core/i18n/i18n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import 'models.dart';

/// EVT-009 행사 사진·후기 (학부모). 행사 시작 뒤 대상 자녀의 보호자만 보고 쓸 수 있다.

Options get _me => Options(extra: {'noInstitution': true});
final _dt = DateFormat('M/d HH:mm');

class EventAlbumLink {
  const EventAlbumLink({required this.albumId, required this.title, required this.itemCount});
  final String albumId, title;
  final int itemCount;

  factory EventAlbumLink.fromJson(Map<String, dynamic> j) =>
      EventAlbumLink(albumId: j['albumId'] as String, title: j['title'] as String, itemCount: (j['itemCount'] as num).toInt());
}

class EventReview {
  const EventReview({required this.id, required this.studentName, required this.authorName, required this.body, required this.hidden, required this.mine, required this.createdAt});
  final String id, studentName, authorName, body;
  final bool hidden, mine;
  final DateTime createdAt;

  factory EventReview.fromJson(Map<String, dynamic> j) => EventReview(
        id: j['id'] as String,
        studentName: j['studentName'] as String,
        authorName: j['authorName'] as String,
        body: j['body'] as String,
        hidden: j['hidden'] as bool,
        mine: j['mine'] as bool,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

final eventAlbumsProvider = FutureProvider.autoDispose.family<List<EventAlbumLink>, String>((ref, eventId) async {
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/events/$eventId/albums', options: _me);
  return r.data!.map((e) => EventAlbumLink.fromJson(e as Map<String, dynamic>)).toList();
});

final eventReviewsProvider = FutureProvider.autoDispose.family<List<EventReview>, String>((ref, eventId) async {
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/events/$eventId/reviews', options: _me);
  return r.data!.map((e) => EventReview.fromJson(e as Map<String, dynamic>)).toList();
});

/// 행사 상세 시트 아래에 붙는 사진·후기 영역. 행사가 아직 시작 전이면 아무것도 그리지 않는다.
class EventFollowUpSection extends ConsumerStatefulWidget {
  const EventFollowUpSection({super.key, required this.event});
  final ParentEvent event;

  @override
  ConsumerState<EventFollowUpSection> createState() => _EventFollowUpSectionState();
}

class _EventFollowUpSectionState extends ConsumerState<EventFollowUpSection> {
  final _body = TextEditingController();
  String? _studentId;
  bool _busy = false;
  bool _editing = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sid = _studentId ?? (widget.event.children.isNotEmpty ? widget.event.children.first.studentId : null);
    if (sid == null || _body.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).dio.put<Map<String, dynamic>>('me/events/${widget.event.id}/review',
          options: _me, data: {'studentId': sid, 'body': _body.text.trim()});
      ref.invalidate(eventReviewsProvider(widget.event.id));
      setState(() => _editing = false);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).dio.delete<void>('me/events/${widget.event.id}/review', options: _me);
      _body.clear();
      ref.invalidate(eventReviewsProvider(widget.event.id));
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    if (e.canceled || e.startsAt.isAfter(DateTime.now())) return const SizedBox.shrink();
    final albums = ref.watch(eventAlbumsProvider(e.id));
    final reviews = ref.watch(eventReviewsProvider(e.id));
    final mine = reviews.valueOrNull?.where((r) => r.mine).firstOrNull;
    final writing = mine == null || _editing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text(ref.t('행사 사진'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        albums.when(
          loading: () => const LinearProgress(),
          error: (err, _) => Text(errorMessage(err), style: const TextStyle(color: AppColors.error)),
          data: (list) => list.isEmpty
              ? const Text('아직 올라온 사진이 없어요', style: TextStyle(color: AppColors.muted))
              : Column(children: [
                  for (final a in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(a.title),
                      subtitle: Text('사진 ${a.itemCount}장'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/albums/${a.albumId}');
                      },
                    ),
                ]),
        ),
        const Divider(height: 28),
        Text(ref.t('후기'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (writing) ...[
          if (e.children.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                value: _studentId ?? e.children.first.studentId,
                decoration: const InputDecoration(labelText: '자녀', isDense: true),
                items: [for (final c in e.children) DropdownMenuItem(value: c.studentId, child: Text(c.name))],
                onChanged: (v) => setState(() => _studentId = v),
              ),
            ),
          TextField(
            controller: _body,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '행사는 어떠셨나요? 선생님과 다른 보호자에게 보입니다.', isDense: true),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (_editing) TextButton(onPressed: _busy ? null : () => setState(() => _editing = false), child: const Text('취소')),
            FilledButton(onPressed: _busy ? null : _save, child: Text(mine == null ? '후기 남기기' : '수정')),
          ]),
        ],
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
        reviews.when(
          loading: () => const SizedBox.shrink(),
          error: (err, _) => Text(errorMessage(err), style: const TextStyle(color: AppColors.error)),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (list.isEmpty) const Text('첫 후기를 남겨 주세요', style: TextStyle(color: AppColors.muted)),
              for (final r in list)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: r.mine ? AppColors.primary.withValues(alpha: 0.06) : AppColors.muted.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text('${r.studentName} 보호자 · ${_dt.format(r.createdAt)}${r.hidden ? ' · 선생님이 숨김' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                      if (r.mine && !_editing) ...[
                        InkWell(
                          onTap: _busy
                              ? null
                              : () => setState(() {
                                    _editing = true;
                                    _body.text = r.body;
                                  }),
                          child: const Padding(padding: EdgeInsets.all(4), child: Text('수정', style: TextStyle(fontSize: 12))),
                        ),
                        InkWell(
                          onTap: _busy ? null : _delete,
                          child: const Padding(padding: EdgeInsets.all(4), child: Text('삭제', style: TextStyle(fontSize: 12, color: AppColors.error))),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(r.body, style: const TextStyle(height: 1.5)),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class LinearProgress extends StatelessWidget {
  const LinearProgress({super.key});
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
}
