import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/status_badge.dart';
import 'models.dart';
import 'teacher_providers.dart';

/// ATT-006 하원 — 다음 목적지 고르기 (학부모 하원 푸시에 "→ 셔틀 1호차" 로 함께 간다)
Future<Destination?> showDestinationSheet(BuildContext context, {required String studentName}) {
  return showModalBottomSheet<Destination>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DestinationSheet(studentName: studentName),
  );
}

class _DestinationSheet extends ConsumerWidget {
  const _DestinationSheet({required this.studentName});
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dests = ref.watch(destinationsProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('$studentName 하원 — 어디로 가나요?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: dests.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(errorMessage(e)),
                    TextButton(onPressed: () => ref.invalidate(destinationsProvider), child: const Text('다시 시도')),
                  ]),
                ),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('등록된 하원 목적지가 없습니다.\n관리자 웹 설정 > 하원 목적지에서 추가해 주세요.', textAlign: TextAlign.center),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
                          onPressed: () => Navigator.of(context).pop(list[i]),
                          child: Row(children: [
                            Icon(_icon(list[i].type), size: 20),
                            const SizedBox(width: 12),
                            Text(list[i].name, style: const TextStyle(fontSize: 16)),
                          ]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String type) => switch (type) {
        'HOME' => Icons.home_outlined,
        'ACADEMY' => Icons.school_outlined,
        'SHUTTLE' => Icons.directions_bus_outlined,
        _ => Icons.place_outlined,
      };
}

typedef StatusChangeSubmit = Future<void> Function(AttendanceStatus to, String reason, bool? isLate, bool? isEarlyLeave);

/// ATT-002 수동 변경 (잘못 누름 정정·기기 없이 수기 처리). 사유 필수 — 이벤트 로그·감사 로그에 남는다.
/// 학부모에게 정정 푸시는 가지 않는다.
Future<bool?> showStatusChangeSheet(BuildContext context, Attendance a, StatusChangeSubmit submit) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _StatusChangeSheet(a: a, submit: submit),
    ),
  );
}

class _StatusChangeSheet extends StatefulWidget {
  const _StatusChangeSheet({required this.a, required this.submit});
  final Attendance a;
  final StatusChangeSubmit submit;

  @override
  State<_StatusChangeSheet> createState() => _StatusChangeSheetState();
}

class _StatusChangeSheetState extends State<_StatusChangeSheet> {
  late AttendanceStatus _to = widget.a.status == AttendanceStatus.scheduled ? AttendanceStatus.absent : widget.a.status;
  late bool _late = widget.a.isLate;
  late bool _early = widget.a.isEarlyLeave;
  late final _reason = TextEditingController(text: widget.a.absenceReason ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(
        _to,
        _reason.text.trim(),
        _to == AttendanceStatus.absent ? null : _late,
        _to == AttendanceStatus.out ? _early : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Text('${a.studentName} 출결 수동 변경', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              StatusBadge(a.status, isLate: a.isLate, isEarlyLeave: a.isEarlyLeave),
            ]),
            const SizedBox(height: 16),
            SegmentedButton<AttendanceStatus>(
              segments: const [
                ButtonSegment(value: AttendanceStatus.inClass, label: Text('등원')),
                ButtonSegment(value: AttendanceStatus.out, label: Text('하원')),
                ButtonSegment(value: AttendanceStatus.absent, label: Text('결석')),
              ],
              selected: {_to},
              onSelectionChanged: (s) => setState(() => _to = s.first),
            ),
            if (_to != AttendanceStatus.absent)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _late,
                onChanged: (v) => setState(() => _late = v ?? false),
                title: const Text('지각'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if (_to == AttendanceStatus.out)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _early,
                onChanged: (v) => setState(() => _early = v ?? false),
                title: const Text('조퇴'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _to == AttendanceStatus.absent ? '사유 (결석 사유로도 저장)' : '변경 사유',
                hintText: '예: 잘못 눌러 정정, 어머니 전화로 결석 확인',
              ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _reason.text.trim().isEmpty || _busy ? null : _save, child: const Text('변경')),
          ],
        ),
      ),
    );
  }
}
