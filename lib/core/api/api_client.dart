import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../app/flavor.dart';
import '../auth/models.dart';
import '../auth/token_storage.dart';

/// 메모리에 들고 있는 현재 세션 (토큰·선택 기관). 저장소와 함께 갱신한다.
class SessionStore {
  SessionStore(this.storage);

  final TokenStorage storage;
  TokenPair? tokens;
  String? institutionId;

  Future<void> load() async {
    tokens = await storage.readTokens();
    institutionId = await storage.readInstitution();
  }

  Future<void> saveTokens(TokenPair t) async {
    tokens = t;
    await storage.writeTokens(t);
  }

  Future<void> saveInstitution(String? id) async {
    institutionId = id;
    await storage.writeInstitution(id);
  }

  Future<void> clear() async {
    tokens = null;
    institutionId = null;
    await storage.clearSession();
  }
}

/// 백엔드 REST 클라이언트.
/// - Authorization: access (만료 임박이면 먼저 refresh), 401 이면 refresh 후 1회 재시도
/// - refresh 는 한 번에 하나만 (백엔드가 회전 + 재사용 탐지 → 동시에 두 번 쓰면 로그인 계열 전체가 폐기됨)
/// - X-Institution-Id: 선택된 기관 (학부모 /me API 는 options.extra['noInstitution'])
class ApiClient {
  ApiClient(this.session, {required this.onSessionExpired})
      : _raw = Dio(_options()),
        dio = Dio(_options()) {
    dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final SessionStore session;

  /// refresh 가 실패하면 (만료·탈취 탐지) 로그인 화면으로
  final void Function() onSessionExpired;

  final Dio dio;

  /// 로그인·refresh 용 (인터셉터 없음)
  final Dio _raw;

  Future<TokenPair?>? _refreshing;

  static BaseOptions _options() => BaseOptions(
        baseUrl: '${Env.apiBaseUrl}/api/v1/',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        contentType: 'application/json',
        responseType: ResponseType.json,
      );

  static const _uuid = Uuid();

  /// 쓰기 API 재시도용 키. 같은 동작을 다시 보낼 땐 같은 키를 쓴다 (출결 중복 방지)
  static String newIdempotencyKey() => _uuid.v4();

  Future<Map<String, dynamic>> login(String loginId, String password) async {
    final res = await _raw.post<Map<String, dynamic>>('auth/login', data: {'loginId': loginId, 'password': password, 'rememberMe': true});
    return res.data!;
  }

  /// 로그인 전 공개 API (학부모 가입·약관 조회)
  Future<T> publicGet<T>(String path, {Map<String, dynamic>? query}) async {
    final res = await _raw.get<T>(path, queryParameters: query);
    return res.data as T;
  }

  Future<Map<String, dynamic>> publicPost(String path, Object data) async {
    final res = await _raw.post<Map<String, dynamic>>(path, data: data);
    return res.data!;
  }

  /// 서버 세션 종료 (실패해도 로컬은 지운다)
  Future<void> logout() async {
    final rt = session.tokens?.refreshToken;
    if (rt == null) return;
    try {
      await _raw.post<void>('auth/logout', data: {'refreshToken': rt});
    } on DioException {
      // 오프라인이어도 로그아웃은 진행 (refresh 는 만료 시 서버에서 자연 정리)
    }
  }

  /// STOMP CONNECT 용 — 만료 임박이면 갱신해서 준다
  Future<String?> freshAccessToken() async {
    final t = session.tokens;
    if (t == null) return null;
    if (!t.accessExpired) return t.accessToken;
    return (await _refresh())?.accessToken;
  }

  Future<TokenPair?> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<TokenPair?> _doRefresh() async {
    final rt = session.tokens?.refreshToken;
    if (rt == null) return null;
    try {
      final res = await _raw.post<Map<String, dynamic>>('auth/refresh', data: {'refreshToken': rt});
      final pair = TokenPair.fromJson(res.data!);
      await session.saveTokens(pair);
      return pair;
    } on DioException catch (e) {
      // 응답을 받았는데 거절(401 등)이면 세션 끝. 네트워크 오류면 토큰을 지우지 않는다.
      if (e.response != null) {
        await session.clear();
        onSessionExpired();
      }
      return null;
    }
  }

  Future<void> _onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    var t = session.tokens;
    if (t != null && t.accessExpired) t = await _refresh() ?? session.tokens;
    if (t != null) o.headers['Authorization'] = 'Bearer ${t.accessToken}';
    final inst = session.institutionId;
    if (inst != null && o.extra['noInstitution'] != true) o.headers['X-Institution-Id'] = inst;
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    if (e.response?.statusCode != 401 || o.extra['retried'] == true || session.tokens == null) {
      return h.next(e);
    }
    final pair = await _refresh();
    if (pair == null) return h.next(e);
    o.extra['retried'] = true;
    o.headers['Authorization'] = 'Bearer ${pair.accessToken}';
    try {
      h.resolve(await _raw.fetch<dynamic>(o));
    } on DioException catch (err) {
      h.next(err);
    }
  }
}
