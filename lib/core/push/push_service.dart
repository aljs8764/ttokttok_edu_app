import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/flavor.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// 서버가 보내는 푸시 data (ParentServices·EventServices):
///  - {type: attendance, studentId, status, occurredAt}  등·하원 (학생앱 QR 포함)
///  - {type: notice, noticeId, kind}                      알림장·공지·재발송
///  - {type: event, eventId, kind}                        행사 등록·독촉·변경·취소
/// 교사앱은 같은 type 으로 작성자 안내를 받는다 (예약 알림장 발송 완료 = notice, 행사 자동 독촉 결과 = event)
class PushPayload {
  const PushPayload(this.data);

  final Map<String, String> data;

  String? get type => data['type'];

  factory PushPayload.fromMessage(RemoteMessage m) => PushPayload(m.data.map((k, v) => MapEntry(k, '$v')));

  factory PushPayload.decode(String json) =>
      PushPayload((jsonDecode(json) as Map<String, dynamic>).map((k, v) => MapEntry(k, '$v')));

  String encode() => jsonEncode(data);
}

/// 백그라운드·종료 상태 수신. notification 메시지는 OS 가 직접 띄우므로 할 일이 없다.
/// (최상위 함수 + entry-point 표시가 있어야 릴리스 빌드에서 지워지지 않는다)
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

/// FCM 푸시 (스펙 6장 알림). 교사앱·학부모앱만 — 학생앱은 계정이 없어 푸시를 받지 않는다.
///
/// - 로그인 상태가 되면 권한 요청 → 토큰 발급 → PUT /me/devices {flavor, platform, token}
/// - 토큰이 바뀌면 다시 등록, 로그아웃 직전 DELETE /me/devices 로 해제
/// - 앱이 앞에 있을 때: 안드로이드는 로컬 알림으로 띄우고, iOS 는 FCM 표시 옵션으로 배너를 띄운다
/// - 알림을 눌러 들어오면 [taps] 로 알린다 (앱 라우팅은 app/push_navigation.dart)
///
/// Firebase 설정 파일(google-services.json / GoogleService-Info.plist)이 없으면 조용히 꺼진다.
class PushService {
  PushService(this._ref);

  final Ref _ref;

  bool _ready = false;
  bool get enabled => _ready;

  String? _token;
  PushPayload? _pendingTap;

  final _messages = StreamController<PushPayload>.broadcast();
  final _taps = StreamController<PushPayload>.broadcast();

  /// 앱이 앞에 있을 때 받은 푸시 (화면 새로고침용)
  Stream<PushPayload> get messages => _messages.stream;

  /// 알림을 눌러 앱으로 들어옴
  Stream<PushPayload> get taps => _taps.stream;

  /// 알림을 눌러 앱이 새로 켜진 경우 — 첫 화면이 뜬 뒤 한 번 꺼내 쓴다
  PushPayload? takePendingTap() {
    final p = _pendingTap;
    _pendingTap = null;
    return p;
  }

  static const channel = AndroidNotificationChannel(
    'ttok_alerts',
    '똑똑 알림',
    description: '등·하원, 알림장, 행사 알림',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();

  Flavor get _flavor => _ref.read(appConfigProvider).flavor;

  Future<void> init() async {
    if (_flavor == Flavor.student || _ready) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[push] Firebase 설정이 없어 푸시를 끕니다 (flutterfire configure 필요): $e');
      return;
    }
    _ready = true;

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    final fm = FirebaseMessaging.instance;

    if (Platform.isAndroid) {
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) _taps.add(PushPayload.decode(p));
        },
      );
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
      final launch = await _local.getNotificationAppLaunchDetails();
      final p = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && p != null) _pendingTap = PushPayload.decode(p);
    } else {
      // iOS: 앱이 앞에 있어도 배너·소리·배지
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    }

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(PushPayload.fromMessage(m)));
    final initial = await fm.getInitialMessage();
    if (initial != null) _pendingTap = PushPayload.fromMessage(initial);

    fm.onTokenRefresh.listen((t) {
      _token = t;
      unawaited(_register());
    });

    // 로그인(앱 시작 시 세션 복원 포함)되면 등록
    _ref.listen<bool>(authControllerProvider.select((s) => s.loggedIn), (_, loggedIn) {
      if (loggedIn) unawaited(_register());
    }, fireImmediately: true);
  }

  Future<void> _onForeground(RemoteMessage m) async {
    final payload = PushPayload.fromMessage(m);
    _messages.add(payload);
    final n = m.notification;
    if (n == null || !Platform.isAndroid) return;
    await _local.show(
      id: m.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload.encode(),
    );
  }

  bool _permissionAsked = false;

  Future<void> _register() async {
    if (!_ready || !_ref.read(authControllerProvider).loggedIn) return;
    final fm = FirebaseMessaging.instance;
    try {
      if (!_permissionAsked) {
        _permissionAsked = true;
        // iOS·안드로이드 13+ 알림 권한. 거절해도 토큰 등록은 해 둔다 (나중에 설정에서 켤 수 있게)
        await fm.requestPermission(alert: true, badge: true, sound: true);
      }
      _token ??= await fm.getToken();
      final token = _token;
      if (token == null) return;
      await _ref.read(apiClientProvider).dio.put<void>(
            'me/devices',
            data: {'flavor': _flavor.apiName, 'platform': Platform.isIOS ? 'IOS' : 'ANDROID', 'token': token},
            options: Options(extra: {'noInstitution': true}),
          );
    } catch (e) {
      // iOS 시뮬레이터·APNs 미설정이면 토큰을 못 받는다. 다음 로그인·토큰 갱신 때 다시 시도
      debugPrint('[push] 기기 등록 실패: $e');
    }
  }

  /// 로그아웃 직전 (access 토큰이 아직 있을 때) — 이 기기로 더는 푸시를 보내지 않게 한다
  Future<void> unregister() async {
    final token = _token;
    if (!_ready || token == null) return;
    try {
      await _ref.read(apiClientProvider).dio.delete<void>(
            'me/devices',
            data: {'token': token},
            options: Options(extra: {'noInstitution': true}),
          );
    } catch (e) {
      debugPrint('[push] 기기 해제 실패: $e');
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
