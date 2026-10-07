import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/push/push_service.dart';
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

  static const _titles = ['우리 아이', '알림장', '일정·행사', '더보기'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱이 앞에 있을 때 푸시가 오면 해당 목록을 다시 읽는다
    _pushSub = ref.read(pushServiceProvider).messages.listen(_onPush);
    // 개정 약관 재동의 (필수 약관이 남아 있으면 닫을 수 없다)
    WidgetsBinding.instance.addPostFrameCallback((_) => showTermsGateIfNeeded(context, ref));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushSub?.cancel();
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

  /// 학부모 실시간 소켓은 아직 없다(스펙: /user/queue 는 다음 단계) — 앱이 앞으로 오면 다시 읽는다
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
