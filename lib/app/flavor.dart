/// 앱 종류 (스펙: 교사앱·학부모앱 = 하나의 코드베이스, flavor 2개).
/// 진입점이 다르다: lib/main_teacher.dart, lib/main_parent.dart
enum Flavor {
  teacher,
  parent;

  /// 백엔드 AppFlavor (PUT /me/devices)
  String get apiName => name.toUpperCase();

  String get title => this == Flavor.teacher ? '똑똑 선생님' : '똑똑';
}

/// 빌드 시 --dart-define 으로 바꾼다.
/// 안드로이드 에뮬레이터에서 PC 의 localhost 는 10.0.2.2 다.
class Env {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');
  static const wsUrl = String.fromEnvironment('WS_URL', defaultValue: 'ws://10.0.2.2:8080/ws');
}

class AppConfig {
  const AppConfig(this.flavor);
  final Flavor flavor;
}
