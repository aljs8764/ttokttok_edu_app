import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/push/push_service.dart';
import '../../core/realtime/stomp_service.dart';
import 'child_selector.dart';
import 'more_tab.dart';
import 'notices_tab.dart';
import 'parent_providers.dart';
import 'schedule_tab.dart';
import 'terms_gate.dart';
import 'timeline_tab.dart';

/// 학부모앱 홈 — 하단 탭 4개: 안심 타임라인(PAR-001) · 알림장(PAR-004) · 일정·행사(PAR-003·005) · 더보기
/// 위쪽 자녀 선택은 모든 탭에 같이 적용된다.
class ParentHomeScreen extends ConsumerStatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  ConsumerState<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends ConsumerState<ParentHomeScreen> with WidgetsBindingObserver {
  StreamSubscription<PushPayload>? _pushSub;
  StreamSubscription<Map<String, dynamic>>? _userSub;
  Timer? _refreshDebounce;
  final _dirty = <String>{};

  static const _titles = ['우리 아이', '알림장', '일정·행사', '더보기'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱이 앞에 있을 때 푸시가 오면 해당 목록을 다시 읽는다
    _pushSub = ref.read(pushServiceProvider).messages.listen(_onPush);
    // 앱이 켜져 있는 동안엔 개인 큐(/user/queue/events)로 출결·알림장·행사 변화를 바로 받는다
    _userSub = ref.read(stompServiceProvider).watch('/user/queue/events').listen(_onRealtime);
    // 개정 약관 재동의 (필수 약관이 남아 있으면 닫을 수 없다)
    WidgetsBinding.instance.addPostFrameCallback((_) => showTermsGateIfNeeded(context, ref));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushSub?.cancel();
    _userSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void _onPush(PushPayload p) {
    switch (p.type) {
      case 'attendance':
        ref.invalidate(timelineProvider);
      case 'notice':
        ref.invalidate(noticesProvider);
        ref.invalidate(timelineProvider);
      case 'event':
        ref.invalidate(eventsProvider);
      default:
        break;
    }
  }

  void _onRealtime(Map<String, dynamic> m) {
    final type = m['type'];
    if (type is! String) return;
    _dirty.add(type.split('.').first); // attendance · notice · event
    // 푸시와 소켓이 함께 오거나 여러 건이 몰려도 한 번만 다시 읽는다
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final kinds = _dirty.toList();
      _dirty.clear();
      for (final k in kinds) {
        _onPush(PushPayload({'type': k}));
      }
    });
  }

  /// 소켓이 끊겨 있던 사이 변화는 못 받으므로 — 앱이 앞으로 오면 다시 읽는다
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(timelineProvider);
      ref.invalidate(noticesProvider);
      ref.invalidate(eventsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(parentTabProvider);
    final unread = ref.watch(unreadNoticeCountProvider);
    final pendingRsvp = ref.watch(eventsProvider).valueOrNull?.where((e) => e.needsAnswer).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[tab]),
        bottom: tab < 3 ? const PreferredSize(preferredSize: Size.fromHeight(52), child: ChildSelector()) : null,
      ),
      body: IndexedStack(
        index: tab,
        children: const [TimelineTab(), NoticesTab(), ScheduleTab(), MoreTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(parentTabProvider.notifier).state = i,
        indicatorColor: AppColors.primary.withValues(alpha: 0.1),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.mail_outline)),
            selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.mail)),
            label: '알림장',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: pendingRsvp > 0, label: Text('$pendingRsvp'), child: const Icon(Icons.event_outlined)),
            selectedIcon: Badge(isLabelVisible: pendingRsvp > 0, label: Text('$pendingRsvp'), child: const Icon(Icons.event)),
            label: '일정',
          ),
          const NavigationDestination(icon: Icon(Icons.more_horiz), label: '더보기'),
        ],
      ),
    );
  }
}
