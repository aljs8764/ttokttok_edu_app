import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'student_api.dart';

/// STD-002 QR 출석 — 카메라로 입구 QR 을 찍으면 위치와 함께 서버로 보낸다.
/// 서버가 수업 시간·등원 여부를 보고 등원/하원을 정한다 (스펙 7-7).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _Phase { scanning, sending, done, failed }

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _camera = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  _Phase _phase = _Phase.scanning;
  ScanResult? _result;
  String? _error;
  String? _errorCode;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_phase != _Phase.scanning) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.sending);
    await _camera.stop();
    await _send(raw);
  }

  Future<void> _send(String qr, {String? destinationId}) async {
    final api = ref.read(studentApiProvider);
    final pos = await _position();
    // 네트워크 재시도는 같은 키로 (서버가 중복 처리하지 않음). 목적지 선택 후 재요청은 새 키.
    final key = StudentApi.newKey();
    for (var attempt = 0;; attempt++) {
      try {
        final r = await api.scan(
          qr: qr,
          latitude: pos?.latitude,
          longitude: pos?.longitude,
          accuracy: pos?.accuracy,
          destinationId: destinationId,
          idempotencyKey: key,
        );
        if (!mounted) return;
        if (r.outcome == ScanOutcome.chooseDestination) {
          final picked = await _chooseDestination(r);
          if (picked == null) {
            _restart();
            return;
          }
          return _send(qr, destinationId: picked.id);
        }
        HapticFeedback.heavyImpact();
        setState(() {
          _result = r;
          _phase = _Phase.done;
        });
        return;
      } catch (e) {
        final err = ApiException.from(e);
        if (err.isNetwork && attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          continue;
        }
        if (!mounted) return;
        setState(() {
          _error = err.message;
          _errorCode = err.code;
          _phase = _Phase.failed;
        });
        return;
      }
    }
  }

  /// 위치 — 권한이 없거나 꺼져 있으면 null (기관이 위치 확인을 켰다면 서버가 LOCATION_REQUIRED 로 안내)
  Future<Position?> _position() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition().catchError((_) => null);
    }
  }

  Future<DestinationOption?> _chooseDestination(ScanResult r) {
    return showModalBottomSheet<DestinationOption>(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('어디로 가나요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final d in r.destinations)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Text(d.name, style: const TextStyle(fontSize: 18)),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _restart() {
    setState(() {
      _phase = _Phase.scanning;
      _error = null;
      _errorCode = null;
      _result = null;
    });
    unawaited(_camera.start());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR 출석')),
      body: switch (_phase) {
        _Phase.scanning || _Phase.sending => Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _camera,
                onDetect: _onDetect,
                errorBuilder: (_, err) => _CameraError(err.errorCode == MobileScannerErrorCode.permissionDenied),
              ),
              const _Frame(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: Text(
                  _phase == _Phase.sending ? '확인하고 있어요…' : '입구의 QR 을 네모 안에 맞춰 주세요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
                ),
              ),
              if (_phase == _Phase.sending) const Center(child: CircularProgressIndicator(color: Colors.white)),
            ],
          ),
        _Phase.done => _Done(result: _result!, onClose: () => Navigator.of(context).pop()),
        _Phase.failed => _Failed(message: _error ?? '출석하지 못했어요', code: _errorCode, onRetry: _restart),
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
        ),
      );
}

class _CameraError extends StatelessWidget {
  const _CameraError(this.permission);
  final bool permission;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(
          permission ? '카메라 권한을 허용해 주세요.\n설정 → 앱 → 똑똑 출석 → 권한' : '카메라를 켤 수 없어요',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
        ),
      );
}

class _Done extends StatelessWidget {
  const _Done({required this.result, required this.onClose});
  final ScanResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final time = DateFormat('HH:mm').format(DateTime.now());
    final (icon, color, title, sub) = switch (r.outcome) {
      ScanOutcome.checkedIn => (
          Icons.login,
          r.attendance?.isLate == true ? AppColors.warning : AppColors.success,
          r.attendance?.isLate == true ? '도착했어요 (지각)' : '도착했어요',
          '${r.classroomName ?? ''} · $time\n부모님께 알림을 보냈어요',
        ),
      ScanOutcome.checkedOut => (
          Icons.logout,
          AppColors.info,
          '출발했어요',
          '${r.classroomName ?? ''} · $time${r.attendance?.nextDestinationName != null ? '\n→ ${r.attendance!.nextDestinationName}' : ''}\n부모님께 알림을 보냈어요',
        ),
      _ => (Icons.check_circle_outline, AppColors.muted, '오늘 출석은 이미 끝났어요', r.classroomName ?? ''),
    };
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 96, color: color),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 8),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSecondary)),
          const SizedBox(height: 40),
          FilledButton(onPressed: onClose, child: const Text('확인')),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.code, required this.onRetry});
  final String message;
  final String? code;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final hint = switch (code) {
      'OUT_OF_RANGE' => '학원 안에서 다시 찍어 주세요. 위치가 정확하지 않으면 잠깐 기다렸다가 다시 해 보세요.',
      'LOCATION_REQUIRED' => '설정 → 앱 → 똑똑 출석 → 위치 권한을 "앱 사용 중 허용"으로 바꿔 주세요.',
      'QR_INVALID' => '입구의 새 QR 을 찍었는지 확인하고, 계속 안 되면 선생님께 말씀해 주세요.',
      'NO_CLASS_NOW' => '수업 시작 1시간 전부터 출석할 수 있어요.',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline, size: 88, color: AppColors.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
          ],
          const SizedBox(height: 32),
          FilledButton(onPressed: onRetry, child: const Text('다시 찍기')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
        ],
      ),
    );
  }
}
