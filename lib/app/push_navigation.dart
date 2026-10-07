import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/providers.dart';
import '../core/push/push_service.dart';
import '../features/parent/parent_providers.dart';
import 'flavor.dart';
import 'router.dart';

/// 푸시 알림을 눌러 들어왔을 때 해당 화면으로 보낸다 (학부모앱).
///  - notice     → 알림장 탭 + 알림장 상세(열람 처리)
///  - event      → 일정·행사 탭
///  - attendance → 홈(안심 타임라인), 해당 자녀 선택
/// 교사앱은 아직 푸시를 받는 기능이 없어 홈으로만 연다.
void openFromPush(WidgetRef ref, PushPayload p) {
  if (!ref.read(authControllerProvider).loggedIn) return;
  final router = ref.read(routerProvider);
  if (ref.read(appConfigProvider).flavor != Flavor.parent) {
    router.go('/');
    return;
  }
  final tab = ref.read(parentTabProvider.notifier);
  switch (p.type) {
    case 'notice':
      tab.state = 1;
      router.go('/');
      final id = p.data['noticeId'];
      if (id != null) router.push('/notices/$id');
    case 'event':
      tab.state = 2;
      router.go('/');
    case 'attendance':
      tab.state = 0;
      final studentId = p.data['studentId'];
      // 푸시는 원생(기관) id 로 온다 → 그 원생의 아이를 고른다 (스펙 7-8)
      final children = ref.read(childrenProvider).valueOrNull ?? const [];
      for (final c in children) {
        if (studentId != null && c.hasStudent(studentId)) ref.read(selectedChildProvider.notifier).state = c.childId;
      }
      router.go('/');
    default:
      router.go('/');
  }
}
