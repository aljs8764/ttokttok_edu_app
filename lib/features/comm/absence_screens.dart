import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../parent/parent_providers.dart';
import 'comm_models.dart';
import 'comm_repository.dart';
import '../../core/i18n/i18n.dart';

DateFormat get _md => DateFormat(tr('M월 d일 (E)'), dateLocale());

/// ATT-007 학부모: 결석·지각·조퇴 사전 신청 목록 + 새 신청
class ParentAbsenceScreen extends ConsumerWidget {
  const ParentAbsenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myAbsenceRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('결석·지각 신청'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _AbsenceForm());
          if (ok == true) ref.invalidate(myAbsenceRequestsProvider);
        },
        icon: const Icon(Icons.edit_calendar),
        label: Text(tr('신청하기')),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (items) => items.isEmpty
            ? Center(child: Text(tr('신청 내역이 없습니다'), style: TextStyle(color: AppColors.textSecondary)))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = items[i];
                  final today = DateTime.now();
                  final canCancel = r.status == 'SUBMITTED' && !r.date.isBefore(DateTime(today.year, today.month, today.day));
                  return ListTile(
                    title: Text('${r.studentName} · ${r.kindLabel}${r.expectedTime != null ? ' ${r.expectedTime}' : ''}'),
                    subtitle: Text('${_md.format(r.date)} · ${r.institutionName}\n${r.reason}'),
                    isThreeLine: true,
                    trailing: canCancel
                        ? TextButton(
                            onPressed: () async {
                              try {
                                await ref.read(commRepositoryProvider).cancelAbsence(r.id);
                                ref.invalidate(myAbsenceRequestsProvider);
                              } catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
                              }
                            },
                            child: Text(tr('취소')),
                          )
                        : Chip(label: Text(r.statusLabel)),
                  );
                },
              ),
      ),
    );
  }
}

class _AbsenceForm extends ConsumerStatefulWidget {
  const _AbsenceForm();

  @override
  ConsumerState<_AbsenceForm> createState() => _AbsenceFormState();
}

class _AbsenceFormState extends ConsumerState<_AbsenceForm> {
  String? _studentId;
  DateTime _date = DateTime.now();
  String _kind = 'ABSENT';
  TimeOfDay? _time;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => (_busy = true, _error = null));
    try {
      await ref.read(commRepositoryProvider).submitAbsence(
            studentId: _studentId!,
            date: _date,
            kind: _kind,
            reason: _reason.text.trim(),
            expectedTime: _kind != 'ABSENT' && _time != null ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}' : null,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => (_busy = false, _error = errorMessage(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(childrenProvider).valueOrNull ?? const [];
    // 아이 × 다니는 기관 (재원 중인 곳만)
    final options = [
      for (final c in children)
        for (final e in c.enrollments.where((e) => e.status == 'ACTIVE')) (id: e.studentId, label: '${c.name} · ${e.institutionName}'),
    ];
    _studentId ??= options.isNotEmpty ? options.first.id : null;
    final needsTime = _kind != 'ABSENT';
    final valid = _studentId != null && _reason.text.trim().isNotEmpty && (!needsTime || _time != null);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('결석·지각·조퇴 신청'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _studentId,
            decoration: InputDecoration(labelText: tr('아이 · 기관')),
            items: [for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.label))],
            onChanged: (v) => setState(() => _studentId = v),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'ABSENT', label: Text(tr('결석'))),
              ButtonSegment(value: 'LATE', label: Text(tr('지각'))),
              ButtonSegment(value: 'EARLY_LEAVE', label: Text(tr('조퇴'))),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_md.format(_date)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                  if (d != null) setState(() => _date = d);
                },
              ),
            ),
            if (needsTime) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(_time == null ? (_kind == 'LATE' ? tr('도착 예정') : tr('조퇴 시각')) : _time!.format(context)),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
                    if (t != null) setState(() => _time = t);
                  },
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          TextField(controller: _reason, maxLength: 300, maxLines: 3, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('사유'), border: OutlineInputBorder())),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: valid && !_busy ? _submit : null, child: Text(tr('신청')))),
        ]),
      ),
    );
  }
}

/// ATT-007 교직원: 들어온 신청 확인 (교사는 담당 반 원생만)
class StaffAbsenceScreen extends ConsumerWidget {
  const StaffAbsenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffAbsenceRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('결석·지각 신청'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(staffAbsenceRequestsProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorMessage(e))),
          data: (items) => items.isEmpty
              ? ListView(children: [SizedBox(height: 120), Center(child: Text(tr('앞으로 2주간 신청이 없습니다'), style: TextStyle(color: AppColors.textSecondary)))])
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return ListTile(
                      title: Text('${r.studentName} · ${r.kindLabel}${r.expectedTime != null ? ' ${r.expectedTime}' : ''}'),
                      subtitle: Text('${_md.format(r.date)} · ${r.guardianName}\n${r.reason}'),
                      isThreeLine: true,
                      trailing: r.status == 'SUBMITTED'
                          ? FilledButton.tonal(
                              onPressed: () async {
                                try {
                                  await ref.read(commRepositoryProvider).acknowledgeAbsence(r.id);
                                  ref.invalidate(staffAbsenceRequestsProvider);
                                } catch (e) {
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
                                }
                              },
                              child: Text(tr('확인')),
                            )
                          : Chip(label: Text(r.statusLabel)),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
