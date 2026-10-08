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
/// 교사앱 (예약 알림장 발송 완료·행사 자동 독촉 안내):
///  - notice → 알림장 상세(수신 확인)
///  - event  → 행사 상세
///  - chat   → 대화 화면, absence_request → 결석·지각 신청 목록
/// 학부모앱 추가: chat → 대화, survey → 설문 목록, album → 앨범 상세, absence_request → 신청 목록, invoice → 납부 내역
void openFromPush(WidgetRef ref, PushPayload p) {
  if (!ref.read(authControllerProvider).loggedIn) return;
  final router = ref.read(routerProvider);
  final flavor = ref.read(appConfigProvider).flavor;
  if (flavor == Flavor.teacher) {
    router.go('/');
    final id = p.data[p.type == 'event' ? 'eventId' : 'noticeId'];
    if (id != null && p.type == 'notice') router.push('/notices/$id');
    if (id != null && p.type == 'event') router.push('/events/$id');
    if (p.type == 'chat' && p.data['conversationId'] != null) router.push('/chat/${p.data['conversationId']}?title=${Uri.encodeComponent('메시지')}&staff=true');
    if (p.type == 'absence_request') router.push('/absence');
    return;
  }
  if (flavor != Flavor.parent) {
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
    case 'chat':
      router.go('/');
      router.push('/chat');
      final cid = p.data['conversationId'];
      if (cid != null) router.push('/chat/$cid?title=${Uri.encodeComponent('메시지')}&staff=false');
    case 'survey':
      router.go('/');
      router.push('/surveys');
    case 'album':
      router.go('/');
      final aid = p.data['albumId'];
      aid != null ? router.push('/albums/$aid') : router.push('/albums');
    case 'absence_request':
      router.go('/');
      router.push('/absence');
    case 'invoice':
      router.go('/');
      router.push('/invoices');
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
