import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/providers.dart';
import '../features/auth/change_password_screen.dart';
import '../features/auth/institution_select_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/parent_signup_screen.dart';
import '../features/parent/notice_detail_screen.dart';
import '../features/parent/parent_home_screen.dart';
import '../features/student/link_screen.dart';
import '../features/student/scan_screen.dart';
import '../features/student/student_api.dart';
import '../features/student/student_home_screen.dart';
import '../features/teacher/class_attendance_screen.dart';
import '../features/teacher/event_detail_screen.dart';
import '../features/teacher/event_form_screen.dart';
import '../features/teacher/notice_detail_screen.dart';
import '../features/teacher/notice_form_screen.dart';
import '../features/teacher/teacher_shell.dart';
import 'flavor.dart';

/// 인증 상태가 바뀌면 go_router 가 redirect 를 다시 돌게 하는 다리
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref<Object?> ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

/// 학생앱: 기기 연결 상태가 바뀌면 redirect 를 다시 돈다
class _StudentListenable extends ChangeNotifier {
  _StudentListenable(Ref<Object?> ref) {
    ref.listen(studentLinkedProvider, (_, __) => notifyListeners());
  }
}

/// 학생앱 (스펙 7-7) — 로그인 없이 연결 코드 → 홈 → QR 스캔
GoRouter _studentRouter(Ref<Object?> ref) => GoRouter(
      initialLocation: '/',
      refreshListenable: _StudentListenable(ref),
      redirect: (context, state) {
        final linked = ref.read(studentLinkedProvider);
        final loc = state.matchedLocation;
        if (!linked) return loc == '/link' ? null : '/link';
        if (loc == '/link') return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/link', builder: (_, __) => const StudentLinkScreen()),
        GoRoute(path: '/', builder: (_, __) => const StudentHomeScreen()),
        GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      ],
    );

final routerProvider = Provider<GoRouter>((ref) {
  final flavor = ref.watch(appConfigProvider).flavor;
  if (flavor == Flavor.student) return _studentRouter(ref);
  final teacher = flavor == Flavor.teacher;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (!auth.loggedIn) return (loc == '/login' || (!teacher && loc == '/signup')) ? null : '/login';
      // 임시 비밀번호로 들어온 계정은 비밀번호부터 바꾼다 (AUTH-004)
      if (auth.user!.mustChangePassword) return loc == '/password' ? null : '/password';
      if (teacher && auth.membership == null) return loc == '/institution' ? null : '/institution';
      if (loc == '/login' || loc == '/signup' || loc == '/password' || (loc == '/institution' && auth.user!.staffMemberships.length <= 1)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/password', builder: (_, __) => const ChangePasswordScreen(forced: true)),
      GoRoute(path: '/institution', builder: (_, __) => const InstitutionSelectScreen()),
      if (teacher) ...[
        GoRoute(path: '/', builder: (_, __) => const TeacherShell()),
        GoRoute(
          path: '/class/:id',
          builder: (_, s) => ClassAttendanceScreen(classId: s.pathParameters['id']!, className: s.uri.queryParameters['name'] ?? '출결'),
        ),
        // 알림장 (NTC) — /notices/new 가 /notices/:id 보다 먼저 매칭돼야 한다
        GoRoute(path: '/notices/new', builder: (_, __) => const NoticeFormScreen()),
        GoRoute(path: '/notices/:id', builder: (_, s) => TeacherNoticeDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/notices/:id/edit', builder: (_, s) => NoticeFormScreen(id: s.pathParameters['id'])),
        // 행사 (EVT)
        GoRoute(path: '/events/new', builder: (_, __) => const EventFormScreen()),
        GoRoute(path: '/events/:id', builder: (_, s) => TeacherEventDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/events/:id/edit', builder: (_, s) => EventFormScreen(id: s.pathParameters['id'])),
        GoRoute(path: '/settings/password', builder: (_, __) => const ChangePasswordScreen(forced: false)),
      ] else ...[
        GoRoute(path: '/', builder: (_, __) => const ParentHomeScreen()),
        GoRoute(path: '/signup', builder: (_, __) => const ParentSignupScreen()),
        GoRoute(path: '/notices/:id', builder: (_, s) => NoticeDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/settings/password', builder: (_, __) => const ChangePasswordScreen(forced: false)),
      ],
    ],
  );
});
