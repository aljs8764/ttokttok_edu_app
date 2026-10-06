import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/flavor.dart';
import '../api/api_client.dart';
import '../api/api_error.dart';
import '../providers.dart';
import 'models.dart';

enum AuthStatus { loggedOut, loggedIn }

class AuthState {
  const AuthState({required this.status, this.user, this.institutionId, this.expired = false});

  final AuthStatus status;
  final AppUser? user;

  /// 교사앱: 선택한 기관. 학부모앱은 기관을 가로질러 쓰므로 null
  final String? institutionId;

  /// 세션 만료로 로그아웃됐는지 (로그인 화면 안내 문구용)
  final bool expired;

  bool get loggedIn => status == AuthStatus.loggedIn;

  Membership? get membership {
    final id = institutionId;
    if (id == null || user == null) return null;
    for (final m in user!.memberships) {
      if (m.institutionId == id) return m;
    }
    return null;
  }

  static const loggedOut = AuthState(status: AuthStatus.loggedOut);
}

/// 로그인 세션. 앱 시작 때 저장소에서 복원하고(main), 로그인·기관 선택·로그아웃을 처리한다.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => AuthState.loggedOut;

  SessionStore get _session => ref.read(sessionStoreProvider);
  ApiClient get _api => ref.read(apiClientProvider);
  Flavor get _flavor => ref.read(appConfigProvider).flavor;

  /// 저장된 세션으로 바로 들어간다 (토큰이 만료됐으면 첫 요청에서 refresh)
  Future<void> restore() async {
    await _session.load();
    final user = await _session.storage.readUser();
    if (_session.tokens == null || user == null) {
      state = AuthState.loggedOut;
      return;
    }
    state = AuthState(status: AuthStatus.loggedIn, user: user, institutionId: _session.institutionId);
  }

  /// AUTH-001. 교사앱은 교직원 소속이 있어야 하고, 학부모앱은 학부모 소속(또는 자녀 연결 전 계정)이어야 한다.
  Future<void> login(String loginId, String password) async {
    final Map<String, dynamic> json;
    try {
      json = await _api.login(loginId.trim(), password);
    } catch (e) {
      throw ApiException.from(e);
    }
    final user = AppUser.fromJson(json['user'] as Map<String, dynamic>);

    if (_flavor == Flavor.teacher && user.staffMemberships.isEmpty) {
      throw ApiException(403, 'NOT_STAFF', '교직원 계정이 아닙니다. 학부모는 똑똑 학부모 앱을 이용해 주세요');
    }
    if (_flavor == Flavor.parent && user.memberships.isNotEmpty && user.memberships.every((m) => m.role.isStaff)) {
      throw ApiException(403, 'NOT_PARENT', '학부모 계정이 아닙니다. 선생님은 똑똑 선생님 앱을 이용해 주세요');
    }

    await _session.saveTokens(TokenPair.fromJson(json));
    await _session.storage.writeUser(user);
    await _session.storage.writeLastLoginId(loginId.trim());

    String? inst;
    if (_flavor == Flavor.teacher) {
      final staff = user.staffMemberships;
      // 소속이 하나면 바로 선택, 여럿이면 기관 선택 화면
      if (staff.length == 1) inst = staff.first.institutionId;
      if (staff.any((m) => m.institutionId == _session.institutionId)) inst = _session.institutionId;
    }
    await _session.saveInstitution(inst);
    state = AuthState(status: AuthStatus.loggedIn, user: user, institutionId: inst);
  }

  /// 학부모 가입 — 학원에 등록된 보호자 번호와 같으면 자녀가 자동 연결된다.
  /// 가입 화면에서 동의한 약관은 가입 직후 /me/terms/agreements 로 기록한다.
  Future<void> signUpParent({required String name, required String phone, required String password, required List<String> termsIds}) async {
    final Map<String, dynamic> json;
    try {
      json = await _api.publicPost('auth/parents', {'name': name.trim(), 'phone': phone, 'password': password});
    } catch (e) {
      throw ApiException.from(e);
    }
    final user = AppUser.fromJson(json['user'] as Map<String, dynamic>);
    await _session.saveTokens(TokenPair.fromJson(json));
    await _session.storage.writeUser(user);
    await _session.storage.writeLastLoginId(phone);
    await _session.saveInstitution(null);
    if (termsIds.isNotEmpty) {
      try {
        await _api.dio.post<void>('me/terms/agreements', data: {'termsIds': termsIds}, options: Options(extra: {'noInstitution': true}));
      } catch (_) {
        // 실패해도 다음 실행 때 약관 게이트가 다시 묻는다
      }
    }
    state = AuthState(status: AuthStatus.loggedIn, user: user);
  }

  Future<void> selectInstitution(String institutionId) async {
    await _session.saveInstitution(institutionId);
    state = AuthState(status: AuthStatus.loggedIn, user: state.user, institutionId: institutionId);
  }

  /// AUTH-005 — 성공하면 백엔드가 다른 기기 세션을 끊는다. 이 기기는 다시 로그인.
  Future<void> changePassword(String current, String next) async {
    try {
      await _api.dio.put<void>('auth/password', data: {'currentPassword': current, 'newPassword': next});
    } catch (e) {
      throw ApiException.from(e);
    }
    await logout();
  }

  Future<void> logout() async {
    await _api.logout();
    await _session.clear();
    state = AuthState.loggedOut;
  }

  /// refresh 실패 (만료·재사용 탐지)
  void sessionExpired() {
    state = const AuthState(status: AuthStatus.loggedOut, expired: true);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
