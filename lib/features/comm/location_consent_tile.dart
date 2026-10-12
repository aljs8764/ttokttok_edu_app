import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import 'comm_repository.dart';
import '../../core/i18n/i18n.dart';

/// PAR-008 위치 정보 제공 동의 — 끄면 학생앱이 위치를 보내지 않아도 되지만, 위치 확인이 켜진 QR 출석은 처리되지 않을 수 있다
class LocationConsentTile extends ConsumerStatefulWidget {
  const LocationConsentTile({super.key, required this.childId});
  final String childId;

  @override
  ConsumerState<LocationConsentTile> createState() => _LocationConsentTileState();
}

class _LocationConsentTileState extends ConsumerState<LocationConsentTile> {
  bool? _granted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(commRepositoryProvider).locationConsent(widget.childId).then((v) {
      if (mounted) setState(() => _granted = v);
    }).catchError((_) {});
  }

  Future<void> _set(bool v) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(commRepositoryProvider).setLocationConsent(widget.childId, v);
      if (mounted) setState(() => _granted = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 4, right: 4),
      secondary: const Icon(Icons.location_on_outlined, size: 20),
      title: Text(tr('위치 정보 제공 동의')),
      subtitle: Text(tr('학생앱 QR 출석 때 현재 위치를 학원에 확인받는 데 씁니다')),
      value: _granted ?? true,
      onChanged: _granted == null || _busy ? null : _set,
    );
  }
}
