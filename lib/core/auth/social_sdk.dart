import 'package:flutter/services.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import '../i18n/i18n.dart';

/// AUTH-006 카카오·네이버 SDK 로그인 → 서비스 서버로 보낼 access token.
/// 키는 빌드할 때 넣는다 (README):
///   flutter run --dart-define=KAKAO_NATIVE_APP_KEY=... --dart-define=NAVER_LOGIN=true
/// 안드로이드는 gradle 속성(KAKAO_NATIVE_APP_KEY, NAVER_CLIENT_ID, NAVER_CLIENT_SECRET), iOS 는 xcconfig 에도 같은 값을 넣어야 한다.
/// 키가 없으면 버튼을 숨긴다(서버도 꺼져 있으면 숨김).

enum SocialKind { kakao, naver }

extension SocialKindX on SocialKind {
  String get api => name.toUpperCase();
  String get label => this == SocialKind.kakao ? tr('카카오') : tr('네이버');
}

const _kakaoKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
const _naverOn = bool.fromEnvironment('NAVER_LOGIN');

bool socialConfigured(SocialKind k) => k == SocialKind.kakao ? _kakaoKey.isNotEmpty : _naverOn;

void initSocialSdks() {
  if (_kakaoKey.isNotEmpty) KakaoSdk.init(nativeAppKey: _kakaoKey);
}

/// 사용자가 취소하면 null
Future<String?> socialAccessToken(SocialKind k) => k == SocialKind.kakao ? _kakao() : _naver();

Future<String?> _kakao() async {
  try {
    if (await isKakaoTalkInstalled()) {
      try {
        return (await UserApi.instance.loginWithKakaoTalk()).accessToken;
      } on PlatformException catch (e) {
        // 카카오톡 로그인 화면에서 뒤로 가기 → 취소. 그 외(카톡에 계정 없음 등)는 카카오계정 로그인으로
        if (e.code == 'CANCELED') return null;
      }
    }
    return (await UserApi.instance.loginWithKakaoAccount()).accessToken;
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') return null;
    rethrow;
  } on KakaoAuthException catch (e) {
    if (e.error == AuthErrorCause.accessDenied) return null;
    rethrow;
  }
}

Future<String?> _naver() async {
  final r = await FlutterNaverLogin.logIn();
  if (r.status != NaverLoginStatus.loggedIn) return null;
  final t = await FlutterNaverLogin.getCurrentAccessToken();
  return t.isValid() ? t.accessToken : null;
}

/// 앱 로그아웃 때 SDK 세션도 정리 (다음 소셜 로그인 때 계정을 고를 수 있게). 실패해도 무시
Future<void> socialSignOut() async {
  if (_kakaoKey.isNotEmpty) {
    try {
      await UserApi.instance.logout();
    } catch (_) {}
  }
  if (_naverOn) {
    try {
      await FlutterNaverLogin.logOut();
    } catch (_) {}
  }
}
