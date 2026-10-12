import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/realtime/stomp_service.dart';
import 'comm_models.dart';
import 'comm_repository.dart';
import '../../core/i18n/i18n.dart';

/// 대화 목록 — 학부모(`staff: false`)와 교직원(`staff: true`)이 같이 쓴다.
/// 새 메시지가 오면(/user/queue/events chat.message) 목록을 다시 읽는다.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key, required this.staff});

  final bool staff;

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(stompServiceProvider).watch('/user/queue/events').listen((m) {
      if (m['type'] == 'chat.message') ref.invalidate(conversationsProvider(widget.staff));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(conversationsProvider(widget.staff));
    final body = list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(errorMessage(e)),
          TextButton(onPressed: () => ref.invalidate(conversationsProvider(widget.staff)), child: Text(tr('다시 시도'))),
        ]),
      ),
      data: (items) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(conversationsProvider(widget.staff)),
        child: items.isEmpty
            ? ListView(children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    widget.staff ? tr('아직 대화가 없습니다.\n학부모가 알림장에 회신하거나 말을 걸면 여기에 모입니다.') : tr('아직 대화가 없습니다.\n알림장에서 "선생님께 회신"을 눌러 시작해 보세요.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
                  ),
                ),
              ])
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _tile(context, items[i]),
              ),
      ),
    );
    return Scaffold(appBar: AppBar(title: Text(tr('메시지'))), body: body);
  }

  Widget _tile(BuildContext context, Conversation c) {
    final title = widget.staff ? '${c.studentName} · ${c.guardianName}' : '${c.institutionName} · ${c.studentName}';
    return ListTile(
      title: Text(title, style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w600)),
      subtitle: Text(
        [if (c.noticeTitle != null) tr('[회신] {0}', [c.noticeTitle]), c.lastMessagePreview ?? tr('대화를 시작해 보세요')].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: c.noticeTitle != null,
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (c.lastMessageAt != null) Text(DateFormat('M/d HH:mm').format(c.lastMessageAt!), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        if (c.unread > 0) Badge(label: Text('${c.unread}')),
      ]),
      onTap: () async {
        await context.push('/chat/${c.id}?title=${Uri.encodeComponent(title)}&staff=${widget.staff}');
        ref.invalidate(conversationsProvider(widget.staff));
      },
    );
  }
}

/// 대화 화면. 열면 읽음 처리하고, 상대 메시지가 오면(chat.message) 다시 읽는다.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.id, required this.title, required this.staff});

  final String id;
  final String title;
  final bool staff;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _sub;
  List<ChatMessage> _messages = const []; // 오래된 것부터
  Object? _error;
  bool _loading = true;
  bool _sending = false;

  CommRepository get _repo => ref.read(commRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _sub = ref.read(stompServiceProvider).watch('/user/queue/events').listen((m) {
      if (m['type'] == 'chat.message' && m['conversationId'] == widget.id) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.messages(widget.id, staff: widget.staff);
      if (!mounted) return;
      setState(() {
        _messages = list.reversed.toList(); // 서버는 최신순
        _error = null;
        _loading = false;
      });
      unawaited(_repo.markRead(widget.id, staff: widget.staff).catchError((_) {}));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) setState(() => (_error = e, _loading = false));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.send(widget.id, text, staff: widget.staff);
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(errorMessage(_error!)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: InputDecoration(hintText: tr('메시지를 입력하세요'), counterText: '', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send), color: AppColors.primary),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(ChatMessage m) {
    // 내가 보낸 쪽: 교직원 화면이면 STAFF, 학부모 화면이면 PARENT
    final mine = widget.staff ? m.fromStaff : !m.fromStaff;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(m.body, style: TextStyle(color: mine ? Colors.white : Colors.black87, height: 1.4)),
          ),
          Text('${m.senderName} · ${DateFormat('M/d HH:mm').format(m.createdAt)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}
