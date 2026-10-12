import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/i18n/i18n.dart';
import 'community_repository.dart';

// P3-⑦ 익명 커뮤니티 화면 (COM-001~009). 교사앱(계정 메뉴)·학부모앱(더보기)에서 /community 로 들어온다.

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// 규칙 미동의면 동의 창을 띄우고, 동의하면 true
Future<bool> ensureCommunityRules(BuildContext context, WidgetRef ref) async {
  final me = await ref.read(communityMeProvider.future);
  if (me.sanctioned) {
    if (context.mounted) _snack(context, tr('커뮤니티 이용이 제한된 계정입니다'));
    return false;
  }
  if (me.rulesAgreed) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('커뮤니티 이용 규칙')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < communityRules.length; i++)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${i + 1}. ${tr(communityRules[i])}')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('닫기'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('동의하고 시작하기'))),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(communityRepositoryProvider).agreeRules();
    ref.invalidate(communityMeProvider);
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, errorMessage(e));
    return false;
  }
}

/// COM-001 게시판 탭
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(communityBoardsProvider);
    final me = ref.watch(communityMeProvider).valueOrNull;
    return boards.when(
      loading: () => Scaffold(appBar: AppBar(title: Text(tr('커뮤니티'))), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(title: Text(tr('커뮤니티'))), body: Center(child: Text(errorMessage(e)))),
      data: (list) {
        final myAction = IconButton(
          tooltip: tr('내 활동'),
          onPressed: () => context.push('/community/me'),
          icon: Badge(isLabelVisible: (me?.newComments ?? 0) > 0, label: Text('${me?.newComments ?? 0}'), child: const Icon(Icons.person_outline)),
        );
        if (list.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('커뮤니티'))),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(tr('이용할 수 있는 게시판이 없습니다.'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary))),
            ),
          );
        }
        return DefaultTabController(
          length: list.length,
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(tr('커뮤니티')),
                actions: [myAction],
                bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final b in list) Tab(text: b.label)]),
              ),
              body: Column(children: [
                if (me != null && me.sanctioned)
                  MaterialBanner(
                    content: Text(me.sanctionPermanent
                        ? tr('커뮤니티 이용이 영구 제한되었습니다. 사유: {0}', [me.sanctionReason ?? '-'])
                        : tr('{0}까지 커뮤니티 글·댓글 작성이 제한됩니다. 사유: {1}', [DateFormat('yyyy.M.d HH:mm').format(me.sanctionedUntil!), me.sanctionReason ?? '-'])),
                    actions: const [SizedBox.shrink()],
                  ),
                Expanded(child: TabBarView(children: [for (final b in list) _BoardView(board: b)])),
              ]),
              floatingActionButton: FloatingActionButton.extended(
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('글쓰기')),
                onPressed: () async {
                  final board = list[DefaultTabController.of(context).index];
                  if (!await ensureCommunityRules(context, ref)) return;
                  if (!context.mounted) return;
                  final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => CommunityWriteScreen(boardKey: board.key)));
                  if (id != null && context.mounted) context.push('/community/posts/$id');
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardView extends ConsumerStatefulWidget {
  const _BoardView({required this.board});
  final CommunityBoard board;

  @override
  ConsumerState<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends ConsumerState<_BoardView> with AutomaticKeepAliveClientMixin {
  String _sort = 'LATEST';
  String? _category;
  String _q = '';
  final _items = <CommunityPost>[];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = reset ? 0 : _page + 1;
      final r = await ref.read(communityRepositoryProvider).posts(widget.board.key, sort: _sort, category: _category, q: _q, page: page);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(r.items);
        _page = r.page;
        _hasMore = r.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final ctrl = TextEditingController(text: _q);
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('제목·내용 검색')),
        content: TextField(controller: ctrl, autofocus: true, textInputAction: TextInputAction.search, onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('전체'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('검색'))),
        ],
      ),
    );
    if (q == null) return;
    _q = q;
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              SegmentedButton<String>(
                segments: [ButtonSegment(value: 'LATEST', label: Text(tr('최신'))), ButtonSegment(value: 'POPULAR', label: Text(tr('인기')))],
                selected: {_sort},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  _sort = v.first;
                  _load(reset: true);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(label: Text(tr('전체')), selected: _category == null, onSelected: (_) {
                _category = null;
                _load(reset: true);
              }),
              for (final c in communityCategories.entries) ...[
                const SizedBox(width: 4),
                ChoiceChip(label: Text(tr(c.value)), selected: _category == c.key, onSelected: (_) {
                  _category = c.key;
                  _load(reset: true);
                }),
              ],
              IconButton(onPressed: _search, icon: Icon(Icons.search, color: _q.isEmpty ? null : AppColors.accent), tooltip: tr('검색')),
            ]),
          ),
          if (_q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(tr('\'{0}\' 검색 결과', [_q]), style: const TextStyle(color: AppColors.textSecondary)),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(errorMessage(_error!), style: const TextStyle(color: AppColors.error))),
          if (!_loading && _error == null && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(child: Text(_q.isNotEmpty ? tr('검색 결과가 없습니다.') : tr('아직 글이 없습니다. 첫 글을 남겨 보세요.'), style: const TextStyle(color: AppColors.textSecondary))),
            ),
          for (final p in _items) ...[
            CommunityPostTile(post: p, onTap: () async {
              await context.push('/community/posts/${p.id}');
              _load(reset: true);
            }),
            const Divider(height: 1),
          ],
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _hasMore) Center(child: TextButton(onPressed: _load, child: Text(tr('더보기')))),
        ],
      ),
    );
  }
}

class CommunityPostTile extends StatelessWidget {
  const CommunityPostTile({super.key, required this.post, required this.onTap, this.subtitle});
  final CommunityPost post;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    const meta = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return ListTile(
      onTap: onTap,
      title: Row(children: [
        Text('[${tr(communityCategories[post.category] ?? post.category)}] ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Expanded(child: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        if (post.hidden != null) Text(' ${tr('숨김')}', style: const TextStyle(color: AppColors.warning, fontSize: 12)),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (post.preview.isNotEmpty) Text(post.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Row(children: [
          Text(subtitle ?? post.author, style: meta),
          const SizedBox(width: 8),
          Text(communityAgo(post.createdAt), style: meta),
          const SizedBox(width: 8),
          const Icon(Icons.favorite_border, size: 13, color: AppColors.textSecondary),
          Text(' ${post.likeCount}', style: meta),
          const SizedBox(width: 8),
          const Icon(Icons.chat_bubble_outline, size: 13, color: AppColors.textSecondary),
          Text(' ${post.commentCount}', style: meta),
        ]),
      ]),
    );
  }
}

/// COM-002 글쓰기·고치기. 저장하면 글 id 를 돌려준다.
class CommunityWriteScreen extends ConsumerStatefulWidget {
  const CommunityWriteScreen({super.key, required this.boardKey, this.editing});
  final String boardKey;
  final CommunityPostDetail? editing;

  @override
  ConsumerState<CommunityWriteScreen> createState() => _CommunityWriteScreenState();
}

class _CommunityWriteScreenState extends ConsumerState<CommunityWriteScreen> {
  late String _category = widget.editing?.post.category ?? 'FREE';
  late final _title = TextEditingController(text: widget.editing?.post.title ?? '');
  late final _body = TextEditingController(text: widget.editing?.body ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      _snack(context, tr('제목과 내용을 입력해 주세요'));
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      final d = widget.editing == null
          ? await repo.write(widget.boardKey, _category, _title.text, _body.text)
          : await repo.edit(widget.editing!.post.id, _category, _title.text, _body.text);
      if (mounted) Navigator.of(context).pop(d.post.id);
    } catch (e) {
      if (mounted) _snack(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? tr('익명으로 글쓰기') : tr('글 고치기')),
        actions: [TextButton(onPressed: _busy ? null : _save, child: Text(widget.editing == null ? tr('올리기') : tr('저장')))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 6, children: [
          for (final c in communityCategories.entries)
            ChoiceChip(label: Text(tr(c.value)), selected: _category == c.key, onSelected: (_) => setState(() => _category = c.key)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _title, maxLength: 100, decoration: InputDecoration(labelText: tr('제목'))),
        TextField(
          controller: _body,
          maxLength: 5000,
          minLines: 8,
          maxLines: null,
          decoration: InputDecoration(labelText: tr('내용'), helperText: tr('전화번호·이메일은 자동으로 가려집니다'), alignLabelWithHint: true),
        ),
      ]),
    );
  }
}

Future<void> _report(BuildContext context, WidgetRef ref, String type, String id) async {
  var reason = 'ABUSE';
  final memo = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr('신고하기')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in communityReasons.entries)
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: r.key,
              groupValue: reason,
              title: Text(tr(r.value)),
              onChanged: (v) => setState(() => reason = v!),
            ),
          TextField(controller: memo, maxLength: 300, decoration: InputDecoration(labelText: tr('메모 (선택)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('취소'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('신고'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(communityRepositoryProvider).report(type, id, reason, memo.text.trim().isEmpty ? null : memo.text.trim());
    if (context.mounted) _snack(context, tr('신고했습니다. 신고가 쌓이면 자동으로 숨겨지고 운영사가 검토합니다.'));
  } catch (e) {
    if (context.mounted) _snack(context, errorMessage(e));
  }
}

Future<bool> _confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('취소'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('삭제'))),
        ],
      ),
    ) ==
    true;

/// COM-002~004 글 보기 + 익명 댓글
class CommunityPostScreen extends ConsumerStatefulWidget {
  const CommunityPostScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends ConsumerState<CommunityPostScreen> {
  final _text = TextEditingController();
  CommunityComment? _replyTo;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(communityPostProvider(widget.id));

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      _refresh();
    } catch (e) {
      if (mounted) _snack(context, errorMessage(e));
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _busy) return;
    if (!await ensureCommunityRules(context, ref)) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).comment(widget.id, body, parentId: _replyTo?.id);
      _text.clear();
      setState(() => _replyTo = null);
      _refresh();
    } catch (e) {
      if (mounted) _snack(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(communityPostProvider(widget.id));
    final repo = ref.read(communityRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('게시글')),
        actions: [
          if (detail.valueOrNull != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final d = detail.value!;
                switch (v) {
                  case 'edit':
                    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => CommunityWriteScreen(boardKey: d.post.boardKey, editing: d)));
                    if (id != null) _refresh();
                  case 'delete':
                    if (await _confirm(context, tr('이 글을 지울까요?'))) {
                      try {
                        await repo.deletePost(d.post.id);
                        if (context.mounted) context.pop();
                      } catch (e) {
                        if (context.mounted) _snack(context, errorMessage(e));
                      }
                    }
                  case 'report':
                    await _report(context, ref, 'posts', d.post.id);
                }
              },
              itemBuilder: (_) => detail.value!.post.mine
                  ? [PopupMenuItem(value: 'edit', child: Text(tr('고치기'))), PopupMenuItem(value: 'delete', child: Text(tr('삭제')))]
                  : [PopupMenuItem(value: 'report', child: Text(tr('신고')))],
            ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (d) => Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (d.post.hidden != null)
                  Card(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(d.post.hidden == 'REPORTED'
                          ? tr('신고가 쌓여 다른 사람에게는 숨겨진 글입니다. 운영사가 검토 중입니다.')
                          : tr('운영 정책에 따라 숨겨진 글입니다.')),
                    ),
                  ),
                Text(tr(communityCategories[d.post.category] ?? d.post.category), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(d.post.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${d.post.author} · ${communityAgo(d.post.createdAt)}${d.post.mine ? ' · ${tr('내 글')}' : ''}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const Divider(height: 24),
                SelectableText(d.body, style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _run(() => repo.like('posts', d.post.id)),
                    icon: Icon(d.liked ? Icons.favorite : Icons.favorite_border, color: AppColors.error),
                    label: Text(tr('공감 {0}', [d.post.likeCount])),
                  ),
                ),
                const Divider(height: 32),
                Text(tr('댓글 {0}', [d.post.commentCount]), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (d.comments.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('첫 댓글을 남겨 보세요.'), style: const TextStyle(color: AppColors.textSecondary))),
                for (final c in d.comments) _commentTile(c, repo),
              ]),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14000000)))),
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_replyTo != null)
                  Row(children: [
                    Expanded(child: Text(tr('{0}에게 답글', [anonLabel(_replyTo!.anonNo)]), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _replyTo = null), icon: const Icon(Icons.close, size: 16)),
                  ]),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: tr('익명으로 댓글 달기'), counterText: '', border: InputBorder.none),
                    ),
                  ),
                  IconButton(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _commentTile(CommunityComment c, CommunityRepository repo) {
    final gone = c.deleted || c.hidden;
    return Padding(
      padding: EdgeInsets.only(left: c.parentId == null ? 0 : 28, top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (c.parentId != null) const Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.textSecondary),
          Text(anonLabel(c.anonNo), style: TextStyle(fontWeight: FontWeight.w700, color: c.anonNo == 0 ? AppColors.accent : null)),
          if (c.mine) Text(' (${tr('나')})', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(width: 6),
          Text(communityAgo(c.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          if (!gone) ...[
            InkWell(
              onTap: () => _run(() => repo.like('comments', c.id)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  Icon(c.liked ? Icons.favorite : Icons.favorite_border, size: 15, color: AppColors.error),
                  Text(' ${c.likeCount}', style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
            if (c.parentId == null)
              IconButton(visualDensity: VisualDensity.compact, tooltip: tr('답글'), onPressed: () => setState(() => _replyTo = c), icon: const Icon(Icons.reply, size: 18)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: c.mine ? tr('삭제') : tr('신고'),
              icon: Icon(c.mine ? Icons.delete_outline : Icons.outlined_flag, size: 18),
              onPressed: () async {
                if (c.mine) {
                  if (await _confirm(context, tr('이 댓글을 지울까요?'))) await _run(() => repo.deleteComment(c.id));
                } else {
                  await _report(context, ref, 'comments', c.id);
                }
              },
            ),
          ],
        ]),
        Text(
          c.deleted ? tr('삭제된 댓글입니다') : c.hidden ? tr('신고·운영 정책으로 숨겨진 댓글입니다') : (c.body ?? ''),
          style: TextStyle(color: gone ? AppColors.muted : null),
        ),
      ]),
    );
  }
}

/// COM-009 내가 쓴 글·댓글
class CommunityMyScreen extends ConsumerStatefulWidget {
  const CommunityMyScreen({super.key});

  @override
  ConsumerState<CommunityMyScreen> createState() => _CommunityMyScreenState();
}

class _CommunityMyScreenState extends ConsumerState<CommunityMyScreen> {
  List<CommunityPost>? _posts;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 첫 페이지를 보면 '새 댓글' 표시가 지워진다
      final r = await ref.read(communityRepositoryProvider).myPosts();
      if (!mounted) return;
      setState(() => _posts = r.items);
      ref.invalidate(communityMeProvider);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(myCommunityCommentsProvider);
    final boards = ref.watch(communityBoardsProvider).valueOrNull ?? const <CommunityBoard>[];
    String boardName(String key) => boards.where((b) => b.key == key).map((b) => b.label).firstOrNull ?? '';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('내 활동')), bottom: TabBar(tabs: [Tab(text: tr('내 글')), Tab(text: tr('내 댓글'))])),
        body: TabBarView(children: [
          _error != null
              ? Center(child: Text(errorMessage(_error!)))
              : _posts == null
                  ? const Center(child: CircularProgressIndicator())
                  : _posts!.isEmpty
                      ? Center(child: Text(tr('쓴 글이 없습니다.'), style: const TextStyle(color: AppColors.textSecondary)))
                      : ListView.separated(
                          itemCount: _posts!.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => CommunityPostTile(
                            post: _posts![i],
                            subtitle: boardName(_posts![i].boardKey),
                            onTap: () async {
                              await context.push('/community/posts/${_posts![i].id}');
                              _load();
                            },
                          ),
                        ),
          comments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(errorMessage(e))),
            data: (list) => list.isEmpty
                ? Center(child: Text(tr('쓴 댓글이 없습니다.'), style: const TextStyle(color: AppColors.textSecondary)))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        title: Text(c.deleted ? tr('삭제된 댓글입니다') : (c.body ?? ''), maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.deleted ? AppColors.muted : null)),
                        subtitle: Text('${c.postTitle} · ${communityAgo(c.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => context.push('/community/posts/${c.postId}'),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
