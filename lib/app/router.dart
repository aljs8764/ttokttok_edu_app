import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/providers.dart';
import '../features/auth/change_password_screen.dart';
import '../features/auth/institution_select_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/parent/parent_home_screen.dart';
import '../features/teacher/class_attendance_screen.dart';
import '../features/teacher/teacher_home_screen.dart';
import 'flavor.dart';

/// 인증 상태가 바뀌면 go_router 가 redirect 를 다시 돌게 하는 다리
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref<Object?> ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final flavor = ref.watch(appConfigProvider).flavor;
  final teacher = flavor == Flavor.teacher;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (!auth.loggedIn) return loc == '/login' ? null : '/login';
      // 임시 비밀번호로 들어온 계정은 비밀번호부터 바꾼다 (AUTH-004)
      if (auth.user!.mustChangePassword) return loc == '/password' ? null : '/password';
      if (teacher && auth.membership == null) return loc == '/institution' ? null : '/institution';
      if (loc == '/login' || loc == '/password' || (loc == '/institution' && auth.user!.staffMemberships.length <= 1)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/password', builder: (_, __) => const ChangePasswordScreen(forced: true)),
      GoRoute(path: '/institution', builder: (_, __) => const InstitutionSelectScreen()),
      if (teacher) ...[
        GoRoute(path: '/', builder: (_, __) => const TeacherHomeScreen()),
        GoRoute(
          path: '/class/:id',
          builder: (_, s) => ClassAttendanceScreen(classId: s.pathParameters['id']!, className: s.uri.queryParameters['name'] ?? '출결'),
        ),
        GoRoute(path: '/settings/password', builder: (_, __) => const ChangePasswordScreen(forced: false)),
      ] else
        GoRoute(path: '/', builder: (_, __) => const ParentHomeScreen()),
    ],
  );
});
