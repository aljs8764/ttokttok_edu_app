import '../../core/i18n/i18n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/logo_mark.dart';
import '../../core/push/push_service.dart';
import '../../core/realtime/stomp_service.dart';
import 'child_selector.dart';
import 'more_tab.dart';
import 'notices_tab.dart';
import '../comm/billing_screens.dart';
import '../comm/consult_screens.dart';
import '../shuttle/shuttle_screens.dart';
import '../comm/comm_repository.dart';
import 'parent_providers.dart';
import 'schedule_tab.dart';
import 'terms_gate.dart';
import 'timeline_tab.dart';

/// 학부모앱 홈 — 하단 탭 5개(디자인): 홈/안심 타임라인(PAR-001) · 알림장(PAR-004) · 일정(PAR-003) · 행사(PAR-005) · 더보기
/// 위쪽 자녀 선택(PAR-006)은 더보기 외 모든 탭에 같이 적용된다.
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

  static const _titles = ['홈', '알림장', '일정', '행사', '더보기'];

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
      case 'attendance_missing':
        ref.invalidate(timelineProvider);
      case 'notice':
        ref.invalidate(noticesProvider);
        ref.invalidate(timelineProvider);
      case 'event':
        ref.invalidate(eventsProvider);
      case 'chat':
        ref.invalidate(conversationsProvider(false));
      case 'survey':
        ref.invalidate(surveysProvider);
      case 'album':
        ref.invalidate(albumsProvider);
      case 'absence':
      case 'absence_request':
        ref.invalidate(myAbsenceRequestsProvider);
      case 'invoice':
        ref.invalidate(myInvoicesProvider);
      case 'shuttle':
        ref.invalidate(myShuttlesProvider);
      case 'consult':
        ref.invalidate(myConsultsProvider);
        ref.invalidate(availableConsultsProvider);
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

    Widget badged(IconData icon, int n) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(icon));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 20,
        // 홈은 로고, 나머지 탭은 화면 이름
        title: tab == 0
            ? Row(children: [
                const LogoMark(size: 32),
                const SizedBox(width: 8),
                Text(tr('똑똑'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
              ])
            : Text(ref.t(_titles[tab])),
        actions: [
          // 알림 센터 화면(PAR-002)이 생기기 전까지는 알림장 탭으로 보낸다
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: IconButton(
                tooltip: tr('알림'),
                onPressed: () => ref.read(parentTabProvider.notifier).state = 1,
                icon: Badge(smallSize: 8, isLabelVisible: unread > 0, child: const Icon(Icons.notifications_none_rounded)),
              ),
            ),
          ),
        ],
        bottom: tab < 4 ? const PreferredSize(preferredSize: Size.fromHeight(ChildSelector.height), child: ChildSelector()) : null,
      ),
      body: IndexedStack(
        index: tab,
        children: const [
          TimelineTab(),
          NoticesTab(),
          ScheduleTab(section: ScheduleSection.schedule),
          ScheduleTab(section: ScheduleSection.events),
          MoreTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(parentTabProvider.notifier).state = i,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: ref.t('홈')),
          NavigationDestination(
            icon: badged(Icons.chat_bubble_outline, unread),
            selectedIcon: badged(Icons.chat_bubble, unread),
            label: ref.t('알림장'),
          ),
          NavigationDestination(icon: const Icon(Icons.calendar_today_outlined), selectedIcon: const Icon(Icons.calendar_today), label: ref.t('일정')),
          NavigationDestination(
            icon: badged(Icons.flag_outlined, pendingRsvp),
            selectedIcon: badged(Icons.flag, pendingRsvp),
            label: ref.t('행사'),
          ),
          NavigationDestination(icon: const Icon(Icons.menu), label: ref.t('더보기')),
        ],
      ),
    );
  }
}
