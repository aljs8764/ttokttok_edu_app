import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../app/flavor.dart';
import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// STOMP 구독 (스펙 6장). 교사는 담당 반 /topic/class.{반}, 원장·실장은 /topic/inst.{기관}.
/// 메시지는 "바뀌었다"는 신호 + 최소 필드 — 화면은 그걸로 행 하나를 고치거나 REST 로 다시 읽는다.
///
/// CONNECT 헤더에 access 토큰을 싣는데 15분이면 만료되므로, 라이브러리 자동 재연결 대신
/// 끊기면 5초 뒤 새 토큰으로 클라이언트를 새로 만든다.
class StompService {
  StompService(this._api);

  final ApiClient _api;
  StompClient? _client;
  Timer? _retry;
  bool _active = false;

  /// destination → 화면 쪽 스트림
  final _channels = <String, StreamController<Map<String, dynamic>>>{};

  /// destination → 현재 연결의 구독 해제 함수
  final _unsubscribers = <String, void Function()>{};

  final connected = ValueNotifier<bool>(false);

  /// 구독. 처음 듣는 destination 이면 연결돼 있을 때 바로, 아니면 연결되면 구독한다.
  Stream<Map<String, dynamic>> watch(String destination) {
    final ch = _channels.putIfAbsent(destination, () {
      late final StreamController<Map<String, dynamic>> c;
      c = StreamController<Map<String, dynamic>>.broadcast(
        onListen: () => _subscribe(destination),
        onCancel: () {
          _unsubscribers.remove(destination)?.call();
          _channels.remove(destination);
          unawaited(c.close());
        },
      );
      return c;
    });
    _ensureStarted();
    return ch.stream;
  }

  void _ensureStarted() {
    if (_active) return;
    _active = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_active) return;
    final token = await _api.freshAccessToken();
    if (token == null) return; // 로그아웃 상태
    _client = StompClient(
      config: StompConfig(
        url: Env.wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        heartbeatIncoming: const Duration(seconds: 20),
        heartbeatOutgoing: const Duration(seconds: 20),
        reconnectDelay: Duration.zero, // 직접 재연결 (토큰 갱신 때문)
        onConnect: (_) {
          connected.value = true;
          _unsubscribers.clear();
          for (final d in _channels.keys) {
            _subscribe(d);
          }
        },
        onWebSocketError: (_) => _scheduleReconnect(),
        onStompError: (_) => _scheduleReconnect(),
        onWebSocketDone: _scheduleReconnect,
        onDisconnect: (_) => connected.value = false,
      ),
    )..activate();
  }

  void _subscribe(String destination) {
    final c = _client;
    if (c == null || !c.connected || _unsubscribers.containsKey(destination)) return;
    _unsubscribers[destination] = c.subscribe(
      destination: destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null) return;
        try {
          _channels[destination]?.add(jsonDecode(body) as Map<String, dynamic>);
        } catch (_) {
          // 형식이 다른 메시지는 무시
        }
      },
    );
  }

  void _scheduleReconnect() {
    connected.value = false;
    final old = _client;
    _client = null; // deactivate 가 다시 onWebSocketDone 을 부르므로 먼저 비운다
    old?.deactivate();
    _unsubscribers.clear();
    if (!_active) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), () => unawaited(_connect()));
  }

  void stop() {
    _active = false;
    _retry?.cancel();
    final old = _client;
    _client = null;
    old?.deactivate();
    _unsubscribers.clear();
    connected.value = false;
  }
}

/// 로그아웃되면 연결을 끊는다
final stompServiceProvider = Provider<StompService>((ref) {
  final s = StompService(ref.watch(apiClientProvider));
  ref.listen(authControllerProvider, (prev, next) {
    if (!next.loggedIn) s.stop();
  });
  ref.onDispose(s.stop);
  return s;
});

/// 화면에서: ref.listen(realtimeProvider('/topic/class.$id'), ...)
final realtimeProvider = StreamProvider.autoDispose.family<Map<String, dynamic>, String>((ref, destination) {
  return ref.watch(stompServiceProvider).watch(destination);
});
