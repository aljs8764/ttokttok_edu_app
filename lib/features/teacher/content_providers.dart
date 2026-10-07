import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import 'content_models.dart';
import 'content_repository.dart';

/// 페이지 목록 상태 (알림장·행사 공통)
class ListState<T> {
  const ListState({this.items = const [], this.page = 0, this.hasMore = false, this.loadingMore = false});

  final List<T> items;
  final int page;
  final bool hasMore;
  final bool loadingMore;

  ListState<T> copyWith({List<T>? items, int? page, bool? hasMore, bool? loadingMore}) => ListState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// 알림장 발송 이력 (NTC-004). 기관이 바뀌면 다시 읽는다.
/// 알림장 목록 필터 (null = 전체). 서버 파라미터 kind·status 로 보낸다.
class NoticeFilter {
  const NoticeFilter({this.kind, this.status});
  final NoticeKind? kind;
  final NoticeStatus? status;
  bool get isEmpty => kind == null && status == null;
}

class NoticeFilterController extends AutoDisposeNotifier<NoticeFilter> {
  @override
  NoticeFilter build() => const NoticeFilter();

  void setKind(NoticeKind? k) => state = NoticeFilter(kind: k, status: state.status);
  void setStatus(NoticeStatus? s) => state = NoticeFilter(kind: state.kind, status: s);
}

final noticeFilterProvider = NotifierProvider.autoDispose<NoticeFilterController, NoticeFilter>(NoticeFilterController.new);

class NoticeListController extends AutoDisposeAsyncNotifier<ListState<TeacherNotice>> {
  @override
  Future<ListState<TeacherNotice>> build() async {
    ref.watch(authControllerProvider.select((s) => s.institutionId));
    final f = ref.watch(noticeFilterProvider);
    final p = await ref.read(contentRepositoryProvider).notices(0, kind: f.kind, status: f.status);
    return ListState(items: p.items, page: 0, hasMore: p.hasMore);
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final f = ref.read(noticeFilterProvider);
      final p = await ref.read(contentRepositoryProvider).notices(s.page + 1, kind: f.kind, status: f.status);
      state = AsyncData(s.copyWith(items: [...s.items, ...p.items], page: s.page + 1, hasMore: p.hasMore, loadingMore: false));
    } catch (_) {
      // 다음 스크롤 때 다시 시도
      state = AsyncData(s.copyWith(loadingMore: false));
    }
  }
}

final noticesProvider = AsyncNotifierProvider.autoDispose<NoticeListController, ListState<TeacherNotice>>(NoticeListController.new);

/// 행사 목록. 인자 = upcoming (true: 어제 이후 시작 행사, false: 지난 행사 포함 전체)
class EventListController extends AutoDisposeFamilyAsyncNotifier<ListState<SchoolEvent>, bool> {
  late bool _upcoming;

  @override
  Future<ListState<SchoolEvent>> build(bool upcoming) async {
    _upcoming = upcoming;
    ref.watch(authControllerProvider.select((s) => s.institutionId));
    final p = await ref.read(contentRepositoryProvider).events(upcoming: upcoming, page: 0);
    return ListState(items: p.items, page: 0, hasMore: p.hasMore);
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final p = await ref.read(contentRepositoryProvider).events(upcoming: _upcoming, page: s.page + 1);
      state = AsyncData(s.copyWith(items: [...s.items, ...p.items], page: s.page + 1, hasMore: p.hasMore, loadingMore: false));
    } catch (_) {
      state = AsyncData(s.copyWith(loadingMore: false));
    }
  }
}

final eventsProvider = AsyncNotifierProvider.autoDispose.family<EventListController, ListState<SchoolEvent>, bool>(EventListController.new);

final noticeDetailProvider = FutureProvider.autoDispose.family<TeacherNotice, String>((ref, id) => ref.watch(contentRepositoryProvider).notice(id));

final noticeReceiptsProvider = FutureProvider.autoDispose.family<NoticeReceipts, String>((ref, id) => ref.watch(contentRepositoryProvider).receipts(id));

final eventSummaryProvider = FutureProvider.autoDispose.family<EventSummary, String>((ref, id) => ref.watch(contentRepositoryProvider).eventSummary(id));

/// 알림장·행사를 만들거나 바꾼 뒤 목록·대시보드가 다시 읽도록
void invalidateNotices(WidgetRef ref, {String? id}) {
  ref.invalidate(noticesProvider);
  if (id != null) {
    ref.invalidate(noticeDetailProvider(id));
    ref.invalidate(noticeReceiptsProvider(id));
  }
}

void invalidateEvents(WidgetRef ref, {String? id}) {
  ref.invalidate(eventsProvider);
  if (id != null) ref.invalidate(eventSummaryProvider(id));
}
