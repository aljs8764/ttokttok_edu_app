import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../parent/parent_providers.dart';
import '../../core/i18n/i18n.dart';

/// Phase 2 ⑥ ATT-009 셔틀버스 실시간 GPS.
/// - 교사앱(기사): 노선을 골라 운행 시작 → 폰 위치를 모아 10초마다 서버로 보낸다(안드로이드는 화면이 꺼져도 알림을 띄운 채 계속).
/// - 학부모앱: 우리 아이 정류장까지 도착 예정 시간과 셔틀 위치를 지도로 본다(10초마다 갱신).
/// 지도는 OpenStreetMap 타일(키 불필요). 운영 규모가 커지면 타일 서버를 바꿔야 한다.

const _tileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
final _hm = DateFormat('HH:mm');
final _hms = DateFormat('HH:mm:ss');

// ───────── 모델 ─────────
class ShuttleStopEta {
  const ShuttleStopEta({required this.id, required this.seq, required this.name, required this.lat, required this.lng, required this.passed, this.etaMinutes});
  final String id, name;
  final int seq;
  final double lat, lng;
  final bool passed;
  final int? etaMinutes;

  LatLng get point => LatLng(lat, lng);

  factory ShuttleStopEta.fromJson(Map<String, dynamic> j) => ShuttleStopEta(
        id: j['id'] as String,
        seq: (j['seq'] as num).toInt(),
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        passed: j['passed'] as bool? ?? false,
        etaMinutes: (j['etaMinutes'] as num?)?.toInt(),
      );
}

class ShuttlePosition {
  const ShuttlePosition({required this.lat, required this.lng, required this.at, this.speedKmh});
  final double lat, lng;
  final DateTime at;
  final double? speedKmh;

  LatLng get point => LatLng(lat, lng);

  static ShuttlePosition? fromJson(Object? o) {
    if (o is! Map<String, dynamic>) return null;
    return ShuttlePosition(
      lat: (o['lat'] as num).toDouble(),
      lng: (o['lng'] as num).toDouble(),
      at: DateTime.parse(o['at'] as String).toLocal(),
      speedKmh: (o['speedKmh'] as num?)?.toDouble(),
    );
  }
}

class ShuttleRouteItem {
  const ShuttleRouteItem({required this.id, required this.name, this.vehicleName, this.plateNo, required this.stopCount, required this.riderCount, this.runningTripId});
  final String id, name;
  final String? vehicleName, plateNo, runningTripId;
  final int stopCount, riderCount;

  factory ShuttleRouteItem.fromJson(Map<String, dynamic> j) => ShuttleRouteItem(
        id: j['id'] as String,
        name: j['name'] as String,
        vehicleName: j['vehicleName'] as String?,
        plateNo: j['plateNo'] as String?,
        stopCount: (j['stops'] as List).length,
        riderCount: (j['riderCount'] as num?)?.toInt() ?? 0,
        runningTripId: j['runningTripId'] as String?,
      );
}

class TripLive {
  const TripLive({required this.id, required this.routeName, required this.status, required this.startedAt, this.position, required this.stale, required this.stops});
  final String id, routeName, status;
  final DateTime startedAt;
  final ShuttlePosition? position;
  final bool stale;
  final List<ShuttleStopEta> stops;

  bool get running => status == 'RUNNING';

  factory TripLive.fromJson(Map<String, dynamic> j) => TripLive(
        id: j['id'] as String,
        routeName: j['routeName'] as String,
        status: j['status'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String).toLocal(),
        position: ShuttlePosition.fromJson(j['position']),
        stale: j['stale'] as bool? ?? false,
        stops: (j['stops'] as List).map((e) => ShuttleStopEta.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class MyShuttle {
  const MyShuttle({
    required this.studentName,
    required this.institutionName,
    required this.routeName,
    this.vehicleName,
    this.plateNo,
    this.driverPhone,
    required this.stopName,
    required this.stop,
    this.trip,
  });
  final String studentName, institutionName, routeName, stopName;
  final String? vehicleName, plateNo, driverPhone;
  final LatLng stop;
  final MyShuttleTrip? trip;

  factory MyShuttle.fromJson(Map<String, dynamic> j) {
    final route = j['route'] as Map<String, dynamic>;
    final stop = j['stop'] as Map<String, dynamic>;
    final trip = j['trip'] as Map<String, dynamic>?;
    return MyShuttle(
      studentName: j['studentName'] as String,
      institutionName: j['institutionName'] as String? ?? '',
      routeName: route['name'] as String,
      vehicleName: route['vehicleName'] as String?,
      plateNo: route['plateNo'] as String?,
      driverPhone: route['driverPhone'] as String?,
      stopName: stop['name'] as String,
      stop: LatLng((stop['lat'] as num).toDouble(), (stop['lng'] as num).toDouble()),
      trip: trip == null ? null : MyShuttleTrip.fromJson(trip),
    );
  }
}

class MyShuttleTrip {
  const MyShuttleTrip({this.position, required this.stale, required this.passed, this.etaMinutes, required this.stopsBefore});
  final ShuttlePosition? position;
  final bool stale, passed;
  final int? etaMinutes;
  final int stopsBefore;

  factory MyShuttleTrip.fromJson(Map<String, dynamic> j) => MyShuttleTrip(
        position: ShuttlePosition.fromJson(j['position']),
        stale: j['stale'] as bool? ?? false,
        passed: j['passed'] as bool? ?? false,
        etaMinutes: (j['etaMinutes'] as num?)?.toInt(),
        stopsBefore: (j['stopsBefore'] as num?)?.toInt() ?? 0,
      );
}

// ───────── 공용 지도 ─────────
class ShuttleMap extends StatelessWidget {
  const ShuttleMap({super.key, required this.stops, this.vehicle, this.highlight, this.height = 260, this.vehicleStale = false});
  final List<ShuttleStopEta> stops;
  final LatLng? vehicle;
  final LatLng? highlight;
  final double height;
  final bool vehicleStale;

  @override
  Widget build(BuildContext context) {
    final pts = <LatLng>[...stops.map((s) => s.point), if (vehicle != null) vehicle!, if (highlight != null) highlight!];
    final center = vehicle ?? highlight ?? (pts.isNotEmpty ? pts.first : const LatLng(37.5665, 126.978));
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            initialCameraFit: pts.length > 1 ? CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(36), maxZoom: 16) : null,
          ),
          children: [
            TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'kr.ttoktok.app'),
            if (stops.length > 1)
              PolylineLayer(polylines: [Polyline(points: stops.map((s) => s.point).toList(), color: AppColors.muted, strokeWidth: 3)]),
            MarkerLayer(markers: [
              for (final s in stops)
                Marker(
                  point: s.point,
                  width: 26,
                  height: 26,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: s.passed ? AppColors.muted : AppColors.primary, width: 2),
                    ),
                    child: Text('${s.seq}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.passed ? AppColors.muted : AppColors.primary)),
                  ),
                ),
              if (highlight != null)
                Marker(point: highlight!, width: 36, height: 36, child: const Icon(Icons.home_rounded, color: AppColors.highlight, size: 32)),
              if (vehicle != null)
                Marker(
                  point: vehicle!,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(color: vehicleStale ? AppColors.muted : AppColors.warning, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 22),
                  ),
                ),
            ]),
            const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
          ],
        ),
      ),
    );
  }
}

// ───────── 교사앱(기사): 운행 ─────────
final shuttleRoutesProvider = FutureProvider.autoDispose<List<ShuttleRouteItem>>((ref) async {
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('shuttle/routes');
  return r.data!.map((e) => ShuttleRouteItem.fromJson(e as Map<String, dynamic>)).toList();
});

class ShuttleDriveScreen extends ConsumerStatefulWidget {
  const ShuttleDriveScreen({super.key});

  @override
  ConsumerState<ShuttleDriveScreen> createState() => _ShuttleDriveScreenState();
}

class _ShuttleDriveScreenState extends ConsumerState<ShuttleDriveScreen> {
  TripLive? _trip;
  StreamSubscription<Position>? _sub;
  Timer? _flushTimer;
  final List<Map<String, dynamic>> _buffer = [];
  double? _lastSpeed;
  bool _busy = false;
  bool _sending = false;
  String? _error;
  DateTime? _lastSent;

  Dio get _dio => ref.read(apiClientProvider).dio;

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = tr('휴대폰 위치(GPS)를 켜 주세요'));
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      setState(() => _error = tr('위치 권한이 필요합니다. 설정에서 허용해 주세요'));
      if (p == LocationPermission.deniedForever) await Geolocator.openAppSettings();
      return false;
    }
    return true;
  }

  LocationSettings get _settings {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: tr('셔틀 운행 중'),
          notificationText: tr('학부모 앱에 셔틀 위치를 보내고 있어요'),
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(accuracy: LocationAccuracy.high, distanceFilter: 10, activityType: ActivityType.automotiveNavigation, pauseLocationUpdatesAutomatically: false);
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
  }

  void _startTracking() {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings).listen((p) {
      _buffer.add({'lat': p.latitude, 'lng': p.longitude, 'recordedAt': p.timestamp.toUtc().toIso8601String()});
      if (_buffer.length > 500) _buffer.removeRange(0, _buffer.length - 500); // 오래 끊기면 오래된 좌표부터 버린다
      _lastSpeed = p.speed >= 0 ? p.speed : null;
    }, onError: (Object e) => setState(() => _error = tr('위치를 받지 못했습니다: {0}', [e])));
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => _flush());
  }

  void _stopTracking() {
    _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<void> _flush() async {
    final trip = _trip;
    if (trip == null || _sending || _buffer.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    try {
      final r = await _dio.post<Map<String, dynamic>>('shuttle/trips/${trip.id}/positions', data: {'points': batch, 'speed': _lastSpeed});
      _buffer.removeRange(0, batch.length.clamp(0, _buffer.length));
      final live = TripLive.fromJson(r.data!);
      if (mounted) {
        setState(() {
          _trip = live;
          _error = null;
          _lastSent = DateTime.now();
        });
      }
      if (!live.running) _stopTracking();
    } on DioException catch (e) {
      final err = ApiException.from(e);
      if (mounted) setState(() => _error = tr('전송 실패(다시 시도합니다): {0}', [err.message]));
      if (e.response?.statusCode == 409 || e.response?.statusCode == 403) _stopTracking();
    } finally {
      _sending = false;
    }
  }

  Future<void> _start(ShuttleRouteItem route) async {
    if (!await _ensurePermission()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final TripLive live;
      if (route.runningTripId != null) {
        // 앱이 꺼졌다 켜진 경우: 이미 시작한 운행을 이어서 (시작한 기사가 아니면 서버가 403)
        final r = await _dio.get<Map<String, dynamic>>('shuttle/trips/${route.runningTripId}');
        live = TripLive.fromJson(r.data!);
      } else {
        final r = await _dio.post<Map<String, dynamic>>('shuttle/routes/${route.id}/trips');
        live = TripLive.fromJson(r.data!);
      }
      setState(() => _trip = live);
      _buffer.clear();
      _startTracking();
      // 첫 위치를 바로 보낸다
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      _buffer.add({'lat': p.latitude, 'lng': p.longitude, 'recordedAt': p.timestamp.toUtc().toIso8601String()});
      await _flush();
    } on DioException catch (e) {
      setState(() => _error = ApiException.from(e).message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    final trip = _trip;
    if (trip == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('운행을 마칠까요?')),
        content: Text(tr('위치 전송을 멈추고 학부모 앱에서도 운행 종료로 보입니다.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('취소'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('운행 종료'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _flush();
      _stopTracking();
      await _dio.post<Map<String, dynamic>>('shuttle/trips/${trip.id}/end');
      setState(() => _trip = null);
      ref.invalidate(shuttleRoutesProvider);
    } on DioException catch (e) {
      setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return PopScope(
      canPop: trip == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('운행 중에는 나갈 수 없습니다. 먼저 운행을 종료해 주세요'))));
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(trip == null ? tr('셔틀 운행') : trip.routeName)),
        body: trip == null ? _routeList() : _running(trip),
      ),
    );
  }

  Widget _routeList() {
    final routes = ref.watch(shuttleRoutesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(shuttleRoutesProvider),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
        Text(tr('운행할 노선을 고르면 이 폰의 위치가 학부모 앱에 실시간으로 보입니다. 운행이 끝나면 꼭 "운행 종료"를 눌러 주세요.'),
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        ...routes.when(
          loading: () => [const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
          error: (e, _) => [Text(ApiException.from(e).message, style: const TextStyle(color: AppColors.error))],
          data: (list) => list.isEmpty
              ? [Text(tr('등록된 노선이 없습니다. 관리자 웹 "셔틀 관제"에서 노선을 먼저 만들어 주세요.'))]
              : [
                  for (final r in list)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.directions_bus_outlined),
                        title: Text(r.name),
                        subtitle: Text([
                          if (r.vehicleName != null) r.vehicleName!,
                          if (r.plateNo != null) r.plateNo!,
                          '정류장 ${r.stopCount}곳 · 탑승 ${r.riderCount}명',
                        ].join(' · ')),
                        trailing: FilledButton(
                          onPressed: _busy || r.stopCount == 0 ? null : () => _start(r),
                          child: Text(r.runningTripId != null ? tr('이어서 운행') : tr('출발')),
                        ),
                      ),
                    ),
                ],
        ),
      ]),
    );
  }

  Widget _running(TripLive trip) {
    final next = trip.stops.where((s) => !s.passed).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      ShuttleMap(stops: trip.stops, vehicle: trip.position?.point, height: 280),
      const SizedBox(height: 12),
      Row(children: [
        Icon(Icons.circle, size: 10, color: _sub != null ? AppColors.success : AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _lastSent == null ? tr('위치 전송 준비 중…') : tr('{0} 전송 · {1} 출발', [_hms.format(_lastSent!), _hm.format(trip.startedAt)]),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final s in trip.stops)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 12, backgroundColor: s.passed ? AppColors.muted : AppColors.primary, child: Text('${s.seq}', style: const TextStyle(fontSize: 11, color: Colors.white))),
              title: Text(s.name, style: TextStyle(color: s.passed ? AppColors.muted : null)),
              trailing: Text(s.passed ? tr('지남') : (s.etaMinutes != null ? tr('약 {0}분', [s.etaMinutes]) : '-')),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      if (next.isEmpty) Text(tr('모든 정류장을 지났습니다.'), textAlign: TextAlign.center),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size.fromHeight(48)),
        onPressed: _busy ? null : _end,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(tr('운행 종료')),
      ),
    ]);
  }
}

// ───────── 학부모앱: 우리 아이 셔틀 ─────────
final myShuttlesProvider = FutureProvider.autoDispose<List<MyShuttle>>((ref) async {
  final child = ref.watch(selectedChildProvider);
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>(
        'me/shuttle',
        options: Options(extra: {'noInstitution': true}),
        queryParameters: {if (child != null) 'childId': child},
      );
  return r.data!.map((e) => MyShuttle.fromJson(e as Map<String, dynamic>)).toList();
});

class MyShuttleScreen extends ConsumerStatefulWidget {
  const MyShuttleScreen({super.key});

  @override
  ConsumerState<MyShuttleScreen> createState() => _MyShuttleScreenState();
}

class _MyShuttleScreenState extends ConsumerState<MyShuttleScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => ref.invalidate(myShuttlesProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myShuttlesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('셔틀 위치'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myShuttlesProvider),
        child: list.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(ApiException.from(e).message))]),
          data: (items) => items.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(tr('셔틀을 이용하는 아이가 없습니다. 학원에서 셔틀 탑승 정류장을 등록하면 여기에 보입니다.'), textAlign: TextAlign.center),
                  ),
                ])
              : ListView(padding: const EdgeInsets.all(16), children: [for (final s in items) _ShuttleCard(item: s)]),
        ),
      ),
    );
  }
}

class _ShuttleCard extends StatelessWidget {
  const _ShuttleCard({required this.item});
  final MyShuttle item;

  String get _status {
    final t = item.trip;
    if (t == null) return tr('지금은 운행 중이 아니에요');
    if (t.passed) return tr('{0} 정류장을 지났어요', [item.stopName]);
    if (t.position == null) return tr('출발했어요 · 위치를 받는 중이에요');
    final eta = t.etaMinutes;
    final head = eta == null ? tr('이동 중') : (eta <= 1 ? tr('곧 도착해요') : tr('약 {0}분 뒤 도착', [eta]));
    return t.stopsBefore > 0 ? tr('{0} · 정류장 {1}곳 전', [head, t.stopsBefore]) : head;
  }

  @override
  Widget build(BuildContext context) {
    final t = item.trip;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item.studentName} · ${item.institutionName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 2),
          Text('${item.routeName}${item.vehicleName != null ? ' · ${item.vehicleName}' : ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(tr('타는 곳: {0}', [item.stopName])),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.directions_bus_rounded, color: t == null ? AppColors.muted : AppColors.warning),
            const SizedBox(width: 6),
            Expanded(child: Text(_status, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (t != null && t.stale)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(tr('잠시 위치 신호가 끊겼어요. 마지막 위치를 보여 드려요.'), style: TextStyle(color: AppColors.warning, fontSize: 12)),
            ),
          if (t?.position != null)
            Text(tr('{0} 기준', [_hms.format(t!.position!.at)]), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          ShuttleMap(stops: const [], vehicle: t?.position?.point, highlight: item.stop, height: 220, vehicleStale: t?.stale ?? false),
          if (item.driverPhone != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:${item.driverPhone}')),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: Text(tr('기사님께 전화')),
              ),
            ),
          Text(tr('도착 예정은 직선거리와 평균 속도로 계산한 추정치예요.'), style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ]),
      ),
    );
  }
}
