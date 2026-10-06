/// 앱 종류 (스펙: 교사앱·학부모앱·학생앱 = 하나의 코드베이스, flavor 3개).
/// 진입점이 다르다: lib/main_teacher.dart, lib/main_parent.dart, lib/main_student.dart
enum Flavor {
  teacher,
  parent,

  /// 학생앱 (스펙 7-7) — 계정 없이 보호자가 연결한 기기 토큰으로 QR 출석만 한다
  student;

  /// 백엔드 AppFlavor (PUT /me/devices) — 학생앱은 푸시 등록 없음
  String get apiName => name.toUpperCase();

  String get title => switch (this) {
        Flavor.teacher => '똑똑 선생님',
        Flavor.parent => '똑똑',
        Flavor.student => '똑똑 출석',
      };
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
