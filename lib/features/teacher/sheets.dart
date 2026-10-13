import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/status_badge.dart';
import 'models.dart';
import 'teacher_providers.dart';
import '../../core/i18n/i18n.dart';

/// ATT-006 하원 — 다음 목적지 고르기 (학부모 하원 푸시에 "→ 셔틀 1호차" 로 함께 간다)
/// [group] = 일괄 하원 (studentName 에 '수업 중 N명' 같은 문구가 온다)
Future<Destination?> showDestinationSheet(BuildContext context, {required String studentName, bool group = false}) {
  return showModalBottomSheet<Destination>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DestinationSheet(studentName: studentName, group: group),
  );
}

/// 디자인(T_Dismiss): 원생 머리 → 목적지 라디오 카드 → 안내 줄 → [하원 처리 → 목적지] (주황)
class _DestinationSheet extends ConsumerStatefulWidget {
  const _DestinationSheet({required this.studentName, this.group = false});
  final String studentName;
  final bool group;

  @override
  ConsumerState<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends ConsumerState<_DestinationSheet> {
  int _pick = 0;

  @override
  Widget build(BuildContext context) {
    final dests = ref.watch(destinationsProvider);
    final list = dests.valueOrNull ?? const <Destination>[];
    final picked = list.isEmpty ? null : list[_pick.clamp(0, list.length - 1)];
    final name = widget.studentName;
    final initial = name.length > 1 ? name.characters.elementAt(1) : (name.characters.firstOrNull ?? '?');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.plannedBg, shape: BoxShape.circle),
                  child: widget.group
                      ? const Icon(Icons.groups_outlined, color: AppColors.plannedFg)
                      : Text(initial, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.plannedFg)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('{0} 하원', [name]), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    Text(tr('지금 {0}', [TimeOfDay.now().format(context)]), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Text(tr('다음 목적지'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Flexible(
                child: dests.when(
                  loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(errorMessage(e)),
                    TextButton(onPressed: () => ref.invalidate(destinationsProvider), child: Text(tr('다시 시도'))),
                  ]),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(tr('등록된 하원 목적지가 없습니다.\n관리자 웹 설정 > 하원 목적지에서 추가해 주세요.'), textAlign: TextAlign.center),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _DestinationOption(
                            d: list[i],
                            icon: _icon(list[i].type),
                            selected: i == _pick,
                            onTap: () => setState(() => _pick = i),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.notifications_none_rounded, size: 16, color: AppColors.plannedFg),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('확인하면 보호자에게 바로 알림이 가요'), style: const TextStyle(fontSize: 13, color: AppColors.plannedFg))),
                ]),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.checkOutButton,
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontFamily: kFontFamily, fontSize: 17, fontWeight: FontWeight.w700),
                ),
                onPressed: picked == null ? null : () => Navigator.of(context).pop(picked),
                child: Text(picked == null ? tr('하원 처리') : tr('하원 처리 → {0}', [picked.name])),
              ),
            ],
          ),
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

class _DestinationOption extends StatelessWidget {
  const _DestinationOption({required this.d, required this.icon, required this.selected, required this.onTap});
  final Destination d;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFFFDF3EA) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? AppColors.checkOutButton : AppColors.line, width: 2),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? AppColors.checkOutButton : const Color(0xFFA3A9B5), width: selected ? 7 : 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(d.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                Icon(icon, size: 20, color: AppColors.plannedFg),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
              Text(tr('{0} 출결 수동 변경', [a.studentName]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              StatusBadge(a.status, isLate: a.isLate, isEarlyLeave: a.isEarlyLeave),
            ]),
            const SizedBox(height: 16),
            SegmentedButton<AttendanceStatus>(
              segments: [
                ButtonSegment(value: AttendanceStatus.inClass, label: Text(tr('등원'))),
                ButtonSegment(value: AttendanceStatus.out, label: Text(tr('하원'))),
                ButtonSegment(value: AttendanceStatus.absent, label: Text(tr('결석'))),
              ],
              selected: {_to},
              onSelectionChanged: (s) => setState(() => _to = s.first),
            ),
            if (_to != AttendanceStatus.absent)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _late,
                onChanged: (v) => setState(() => _late = v ?? false),
                title: Text(tr('지각')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if (_to == AttendanceStatus.out)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _early,
                onChanged: (v) => setState(() => _early = v ?? false),
                title: Text(tr('조퇴')),
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
                labelText: _to == AttendanceStatus.absent ? tr('사유 (결석 사유로도 저장)') : tr('변경 사유'),
                hintText: tr('예: 잘못 눌러 정정, 어머니 전화로 결석 확인'),
              ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _reason.text.trim().isEmpty || _busy ? null : _save, child: Text(tr('변경'))),
          ],
        ),
      ),
    );
  }
}
