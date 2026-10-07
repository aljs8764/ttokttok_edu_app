import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import 'models.dart';
import 'parent_repository.dart';

/// 연결된 자녀 (로그인 사용자가 바뀌면 다시 읽는다)
final childrenProvider = FutureProvider<List<Child>>((ref) {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.watch(parentRepositoryProvider).children();
});

/// 상단 자녀 선택 — null = 전체. 다른 계정으로 로그인하면 초기화
final selectedChildProvider = StateProvider<String?>((ref) {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return null;
});

/// 하단 탭 (0 홈 · 1 알림장 · 2 일정 · 3 더보기). 푸시를 눌러 들어오면 해당 탭으로 옮긴다
final parentTabProvider = StateProvider<int>((ref) {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return 0;
});

/// 커서 페이징 목록 공통 (타임라인·알림장함)
class PagedState<T> {
  const PagedState({this.items = const [], this.loadingMore = false, this.done = false});

  final List<T> items;
  final bool loadingMore;
  final bool done;

  PagedState<T> copyWith({List<T>? items, bool? loadingMore, bool? done}) =>
      PagedState(items: items ?? this.items, loadingMore: loadingMore ?? this.loadingMore, done: done ?? this.done);
}

const _pageSize = 20;

/// PAR-001 타임라인
class TimelineController extends AutoDisposeAsyncNotifier<PagedState<TimelineItem>> {
  @override
  Future<PagedState<TimelineItem>> build() async {
    final child = ref.watch(selectedChildProvider);
    final items = await ref.read(parentRepositoryProvider).timeline(childId: child, limit: _pageSize);
    return PagedState(items: items, done: items.length < _pageSize);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || s.done || s.items.isEmpty) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final more = await ref.read(parentRepositoryProvider).timeline(
            childId: ref.read(selectedChildProvider),
            before: s.items.last.occurredAt,
            limit: _pageSize,
          );
      state = AsyncData(s.copyWith(items: [...s.items, ...more], loadingMore: false, done: more.length < _pageSize));
    } catch (_) {
      state = AsyncData(s.copyWith(loadingMore: false));
    }
  }
}

final timelineProvider = AsyncNotifierProvider.autoDispose<TimelineController, PagedState<TimelineItem>>(TimelineController.new);

/// PAR-004 알림장함
class NoticesController extends AutoDisposeAsyncNotifier<PagedState<ParentNotice>> {
  @override
  Future<PagedState<ParentNotice>> build() async {
    final child = ref.watch(selectedChildProvider);
    final items = await ref.read(parentRepositoryProvider).notices(childId: child, limit: _pageSize);
    return PagedState(items: items, done: items.length < _pageSize);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || s.done || s.items.isEmpty) return;
    final last = s.items.last.sentAt;
    if (last == null) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final more = await ref.read(parentRepositoryProvider).notices(childId: ref.read(selectedChildProvider), before: last, limit: _pageSize);
      state = AsyncData(s.copyWith(items: [...s.items, ...more], loadingMore: false, done: more.length < _pageSize));
    } catch (_) {
      state = AsyncData(s.copyWith(loadingMore: false));
    }
  }

  /// 상세에서 읽으면 목록의 안 읽음 표시도 바로 지운다
  void markRead(String id) {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(items: [for (final n in s.items) n.id == id ? n.markRead() : n]));
  }
}

final noticesProvider = AsyncNotifierProvider.autoDispose<NoticesController, PagedState<ParentNotice>>(NoticesController.new);

final unreadNoticeCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(noticesProvider).valueOrNull?.items.where((n) => n.unread).length ?? 0;
});

/// PAR-005 다가오는 행사 (응답 필요 먼저)
final eventsProvider = FutureProvider.autoDispose<List<ParentEvent>>((ref) async {
  final child = ref.watch(selectedChildProvider);
  final list = await ref.watch(parentRepositoryProvider).events(childId: child);
  list.sort((a, b) {
    final an = a.needsAnswer ? 0 : 1, bn = b.needsAnswer ? 0 : 1;
    return an != bn ? an - bn : a.startsAt.compareTo(b.startsAt);
  });
  return list;
});

/// PAR-003 주간 스케줄 — 주 이동은 weekOffset (0 = 이번 주)
final weekOffsetProvider = StateProvider.autoDispose<int>((ref) => 0);

final scheduleProvider = FutureProvider.autoDispose<WeekSchedule>((ref) {
  final child = ref.watch(selectedChildProvider);
  final offset = ref.watch(weekOffsetProvider);
  return ref.watch(parentRepositoryProvider).schedule(childId: child, week: DateTime.now().add(Duration(days: 7 * offset)));
});

final pendingTermsProvider = FutureProvider.autoDispose<List<Terms>>((ref) {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.watch(parentRepositoryProvider).pendingTerms();
});
