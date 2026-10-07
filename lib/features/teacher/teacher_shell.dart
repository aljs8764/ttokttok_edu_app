import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_service.dart';
import '../../core/realtime/stomp_service.dart';
import 'attendance_queue.dart';
import 'content_providers.dart';
import 'events_tab.dart';
import 'notices_tab.dart';
import 'teacher_home_screen.dart';

/// 교사앱 하단 탭 — 출결(반 목록) · 알림장 · 행사. 탭은 처음 열 때 만든다 (시작할 때 불필요한 조회를 줄이려고).
class TeacherShell extends ConsumerStatefulWidget {
  const TeacherShell({super.key});

  @override
  ConsumerState<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends ConsumerState<TeacherShell> {
  int _index = 0;
  final _visited = <int>{0};

  StreamSubscription<Map<String, dynamic>>? _userSub;
  StreamSubscription<PushPayload>? _pushSub;
  Timer? _refreshDebounce;
  final _dirtyNotices = <String>{};
  final _dirtyEvents = <String>{};

  @override
  void initState() {
    super.initState();
    // 지난번에 못 보낸 오프라인 큐가 있으면 읽어서 보낸다
    Future.microtask(() => ref.read(attendanceQueueProvider.notifier).start());
    // 내가 쓴 알림장·행사의 변화 (개인 큐) + 앱이 앞에 있을 때 받은 푸시 → 목록·상세 갱신
    _userSub = ref.read(stompServiceProvider).watch('/user/queue/events').listen(_onRealtime);
    _pushSub = ref.read(pushServiceProvider).messages.listen(_onPush);
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _pushSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void _onRealtime(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == 'notice.read' || type == 'notice.sent') {
      _markDirty(notice: m['noticeId'] as String?);
    } else if (type == 'event.responded') {
      _markDirty(event: m['eventId'] as String?);
    }
  }

  void _onPush(PushPayload p) {
    if (p.type == 'notice') _markDirty(notice: p.data['noticeId']);
    if (p.type == 'event') _markDirty(event: p.data['eventId']);
  }

  /// 수신 확인이 몰려올 수 있어 0.8초 모아서 한 번에 다시 읽는다
  void _markDirty({String? notice, String? event}) {
    if (notice != null) _dirtyNotices.add(notice);
    if (event != null) _dirtyEvents.add(event);
    if (notice == null && event == null) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (_dirtyNotices.isNotEmpty) {
        final ids = _dirtyNotices.toList();
        _dirtyNotices.clear();
        invalidateNotices(ref);
        for (final id in ids) {
          invalidateNotices(ref, id: id);
        }
      }
      if (_dirtyEvents.isNotEmpty) {
        final ids = _dirtyEvents.toList();
        _dirtyEvents.clear();
        invalidateEvents(ref);
        for (final id in ids) {
          invalidateEvents(ref, id: id);
        }
      }
    });
  }

  static const _tabs = <Widget>[TeacherHomeScreen(), TeacherNoticesTab(), TeacherEventsTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (var i = 0; i < _tabs.length; i++) _visited.contains(i) ? _tabs[i] : const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: '출결'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '알림장'),
          NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: '행사'),
        ],
      ),
    );
  }
}
