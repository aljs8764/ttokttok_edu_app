import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/flavor.dart';
import 'core/auth/auth_controller.dart';
import 'core/providers.dart';
import 'core/push/push_service.dart';
import 'features/student/student_api.dart';

/// 세 진입점(main_teacher / main_parent / main_student)의 공통 시작.
/// 저장된 세션을 먼저 복원해서, 로그인돼 있으면 로그인 화면을 거치지 않는다.
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');

  final container = ProviderContainer(overrides: [appConfigProvider.overrideWithValue(AppConfig(flavor))]);
  if (flavor == Flavor.student) {
    // 학생앱은 계정 로그인 없이 기기 토큰만 복원한다
    await container.read(studentApiProvider).restore();
  } else {
    await container.read(authControllerProvider.notifier).restore();
  }

  // FCM: Firebase 설정 파일이 있으면 켜고, 로그인 상태가 되면 PUT /me/devices 로 기기를 등록한다 (학생앱 제외)
  await container.read(pushServiceProvider).init();

  runApp(UncontrolledProviderScope(container: container, child: const TtokApp()));
}
