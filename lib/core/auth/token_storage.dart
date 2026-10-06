import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// 스펙 3장: 앱 토큰은 flutter_secure_storage (iOS Keychain / Android EncryptedSharedPreferences).
/// 사용자 정보·선택 기관도 같이 둔다 — 앱을 다시 켰을 때 로그인 화면 없이 바로 들어가기 위해.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _s;

  static const _access = 'access';
  static const _accessExp = 'access_exp';
  static const _refresh = 'refresh';
  static const _user = 'user';
  static const _institution = 'institution';
  static const _lastLoginId = 'last_login_id';

  Future<TokenPair?> readTokens() async {
    final access = await _s.read(key: _access);
    final exp = await _s.read(key: _accessExp);
    final refresh = await _s.read(key: _refresh);
    if (access == null || exp == null || refresh == null) return null;
    return TokenPair(accessToken: access, refreshToken: refresh, accessExpiresAt: DateTime.parse(exp));
  }

  Future<void> writeTokens(TokenPair t) async {
    await _s.write(key: _access, value: t.accessToken);
    await _s.write(key: _accessExp, value: t.accessExpiresAt.toIso8601String());
    await _s.write(key: _refresh, value: t.refreshToken);
  }

  Future<AppUser?> readUser() async {
    final raw = await _s.read(key: _user);
    return raw == null ? null : AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> writeUser(AppUser u) => _s.write(key: _user, value: jsonEncode(u.toJson()));

  Future<String?> readInstitution() => _s.read(key: _institution);

  Future<void> writeInstitution(String? id) => id == null ? _s.delete(key: _institution) : _s.write(key: _institution, value: id);

  Future<String?> readLastLoginId() => _s.read(key: _lastLoginId);

  Future<void> writeLastLoginId(String id) => _s.write(key: _lastLoginId, value: id);

  /// 로그아웃 — 아이디 기억은 남긴다
  Future<void> clearSession() async {
    for (final k in [_access, _accessExp, _refresh, _user, _institution]) {
      await _s.delete(key: k);
    }
  }
}
