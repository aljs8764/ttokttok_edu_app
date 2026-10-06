import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'models.dart';
import 'parent_repository.dart';

/// PAR-007 학생앱 연결 — 자녀 휴대폰의 "똑똑 출석" 앱에 넣을 8자리 코드를 만들고,
/// 연결된 기기를 보고 해제한다 (스펙 7-7, 자녀당 최대 3대).
Future<void> showStudentDeviceSheet(BuildContext context, Child child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StudentDeviceSheet(child: child),
    );

class _StudentDeviceSheet extends ConsumerStatefulWidget {
  const _StudentDeviceSheet({required this.child});
  final Child child;

  @override
  ConsumerState<_StudentDeviceSheet> createState() => _StudentDeviceSheetState();
}

class _StudentDeviceSheetState extends ConsumerState<_StudentDeviceSheet> {
  StudentLinkCode? _code;
  Duration _left = Duration.zero;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  late Future<List<StudentDeviceInfo>> _devices;

  ParentRepository get _repo => ref.read(parentRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _devices = _repo.studentDevices(widget.child.studentId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _issue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await _repo.issueStudentLinkCode(widget.child.studentId);
      _timer?.cancel();
      setState(() {
        _code = c;
        _left = c.expiresAt.difference(DateTime.now());
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = c.expiresAt.difference(DateTime.now());
        if (!mounted) return;
        setState(() => _left = left.isNegative ? Duration.zero : left);
        if (left.isNegative) {
          _timer?.cancel();
          // 코드를 썼다면 기기가 하나 늘었을 수 있다
          _reloadDevices();
        }
      });
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reloadDevices() => setState(() => _devices = _repo.studentDevices(widget.child.studentId));

  Future<void> _revoke(StudentDeviceInfo d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기기 연결 해제'),
        content: Text('${d.deviceName} 에서 더 이상 QR 출석을 할 수 없게 됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('해제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.revokeStudentDevice(widget.child.studentId, d.id);
      _reloadDevices();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final active = code != null && _left > Duration.zero;
    final mmss = '${_left.inMinutes}:${(_left.inSeconds % 60).toString().padLeft(2, '0')}';
    final fmt = DateFormat('M/d HH:mm');
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.child.name} 학생앱 연결', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              '자녀 휴대폰에 "똑똑 출석" 앱을 설치하고 아래 코드를 입력하면, 학원 입구 QR 로 등원·하원을 직접 찍을 수 있어요.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 16),
            if (active) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code.code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('코드를 복사했어요')));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Text(
                      '${code.code.substring(0, 4)} ${code.code.substring(4)}',
                      style: const TextStyle(fontSize: 34, letterSpacing: 4, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    Text('$mmss 남음 · 눌러서 복사', style: const TextStyle(color: AppColors.textSecondary)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _busy ? null : _issue, child: const Text('새 코드 만들기')),
            ] else
              FilledButton.icon(
                onPressed: _busy ? null : _issue,
                icon: const Icon(Icons.key),
                label: Text(code == null ? '연결 코드 만들기' : '코드가 만료됐어요 · 다시 만들기'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Text('연결된 기기', style: TextStyle(fontWeight: FontWeight.w700))),
              IconButton(onPressed: _reloadDevices, icon: const Icon(Icons.refresh, size: 20)),
            ]),
            FutureBuilder<List<StudentDeviceInfo>>(
              future: _devices,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                if (snap.hasError) return Text(errorMessage(snap.error!), style: const TextStyle(color: AppColors.error));
                final list = snap.data!;
                if (list.isEmpty) return const Text('아직 연결된 기기가 없어요', style: TextStyle(color: AppColors.textSecondary));
                return Column(children: [
                  for (final d in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.phone_android),
                      title: Text(d.deviceName),
                      subtitle: Text('연결 ${fmt.format(d.createdAt)}${d.lastSeenAt != null ? ' · 최근 사용 ${fmt.format(d.lastSeenAt!)}' : ''}'),
                      trailing: TextButton(onPressed: () => _revoke(d), child: const Text('해제')),
                    ),
                  const Text('기기는 최대 3대까지 연결되고, 넘으면 가장 오래된 기기가 자동으로 해제돼요.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}
