import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/flavor.dart';
import 'api/api_client.dart';
import 'auth/auth_controller.dart';
import 'auth/token_storage.dart';

/// main_*.dart 에서 override 한다
final appConfigProvider = Provider<AppConfig>((ref) => throw UnimplementedError('appConfigProvider override 필요'));

/// 앱 시작 때 저장소에서 읽어 둔 세션 (main 에서 override)
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore(TokenStorage()));

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(sessionStoreProvider),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});
