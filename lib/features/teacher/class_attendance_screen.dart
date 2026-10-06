import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/realtime/stomp_service.dart';
import '../../core/widgets/status_badge.dart';
import 'models.dart';
import 'sheets.dart';
import 'teacher_providers.dart';

enum _Filter { all, waiting, inClass, out, absent }

/// 교사앱 메인 — ATT-005 원터치 등원, ATT-006 하원 + 다음 목적지, (길게 눌러) ATT-002 수동 변경.
/// 누르는 즉시 화면이 바뀌고(낙관적), 실패하면 되돌린 뒤 알려 준다. 같은 반을 보는 다른 교사·관리자 화면은 STOMP 로 따라온다.
class ClassAttendanceScreen extends ConsumerStatefulWidget {
  const ClassAttendanceScreen({super.key, required this.classId, required this.className});

  final String classId;
  final String className;

  @override
  ConsumerState<ClassAttendanceScreen> createState() => _ClassAttendanceScreenState();
}

class _ClassAttendanceScreenState extends ConsumerState<ClassAttendanceScreen> with WidgetsBindingObserver {
  _Filter _filter = _Filter.all;
  late DateTime _loadedDay = DateTime.now();

  ClassAttendanceController get _ctrl => ref.read(classAttendanceProvider(widget.classId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 앱이 백그라운드에 있던 동안 놓친 변경·날짜 변경을 따라잡는다
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadedDay = DateTime.now();
      _ctrl.reload();
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : null, duration: const Duration(seconds: 3)));
  }

  Future<void> _checkIn(Attendance a) async {
    HapticFeedback.lightImpact();
    try {
      await _ctrl.checkIn(a);
    } catch (e) {
      if (mounted) _toast('${a.studentName} 등원 실패: ${errorMessage(e)}', error: true);
    }
  }

  Future<void> _checkOut(Attendance a) async {
    final dest = await showDestinationSheet(context, studentName: a.studentName);
    if (dest == null) return;
    HapticFeedback.lightImpact();
    try {
      await _ctrl.checkOut(a, dest);
    } catch (e) {
      if (mounted) _toast('${a.studentName} 하원 실패: ${errorMessage(e)}', error: true);
    }
  }

  Future<void> _manual(Attendance a) async {
    if (a.dayId == null) {
      _toast('오늘 출결 기록이 아직 없어 바꿀 수 없습니다. 등원을 먼저 눌러 주세요');
      return;
    }
    final changed = await showStatusChangeSheet(context, a, (to, reason, isLate, isEarlyLeave) {
      return _ctrl.changeStatus(a, to, reason, isLate: isLate, isEarlyLeave: isEarlyLeave);
    });
    if (changed == true && mounted) _toast('${a.studentName} 출결을 바꿨습니다');
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(classAttendanceProvider(widget.classId));
    final connected = ref.watch(stompServiceProvider).connected;

    // 실시간 — 이 반 토픽
    ref.listen(realtimeProvider('/topic/class.${widget.classId}'), (_, next) {
      final m = next.valueOrNull;
      if (m != null) _ctrl.applyRealtime(m);
    });

    // 자정을 넘겨 화면을 켜 두었으면 새 날짜로
    if (!DateUtils.isSameDay(_loadedDay, DateTime.now())) {
      _loadedDay = DateTime.now();
      Future.microtask(_ctrl.reload);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.className),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: connected,
            builder: (_, on, __) => Tooltip(
              message: on ? '실시간 연결됨' : '실시간 연결 대기 중 (당겨서 새로고침)',
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.circle, size: 10, color: on ? AppColors.success : AppColors.muted),
              ),
            ),
          ),
        ],
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorMessage(e), style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _ctrl.reload, child: const Text('다시 시도')),
          ]),
        ),
        data: (list) {
          final counts = _Counts.of(list);
          final shown = list.where(_match).toList();
          return RefreshIndicator(
            onRefresh: _ctrl.reload,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Summary(counts: counts)),
                SliverToBoxAdapter(child: _FilterBar(value: _filter, counts: counts, onChanged: (f) => setState(() => _filter = f))),
                if (list.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('오늘 출결 대상 원생이 없습니다', style: TextStyle(color: AppColors.textSecondary))),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _StudentRow(
                        a: shown[i],
                        onCheckIn: () => _checkIn(shown[i]),
                        onCheckOut: () => _checkOut(shown[i]),
                        onManual: () => _manual(shown[i]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _match(Attendance a) => switch (_filter) {
        _Filter.all => true,
        _Filter.waiting => a.status == AttendanceStatus.scheduled,
        _Filter.inClass => a.status == AttendanceStatus.inClass,
        _Filter.out => a.status == AttendanceStatus.out,
        _Filter.absent => a.status == AttendanceStatus.absent,
      };
}

class _Counts {
  const _Counts(this.total, this.waiting, this.inClass, this.out, this.absent, this.late);
  final int total, waiting, inClass, out, absent, late;

  factory _Counts.of(List<Attendance> l) => _Counts(
        l.length,
        l.where((a) => a.status == AttendanceStatus.scheduled).length,
        l.where((a) => a.status == AttendanceStatus.inClass).length,
        l.where((a) => a.status == AttendanceStatus.out).length,
        l.where((a) => a.status == AttendanceStatus.absent).length,
        l.where((a) => a.isLate).length,
      );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.counts});
  final _Counts counts;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int n, Color color) => Expanded(
          child: Column(children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE6E8F0))),
      child: Row(children: [
        cell('등원 전', counts.waiting, AppColors.muted),
        cell('수업 중', counts.inClass, AppColors.success),
        cell('하원', counts.out, AppColors.info),
        cell('결석', counts.absent, AppColors.error),
        cell('지각', counts.late, AppColors.warning),
      ]),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.counts, required this.onChanged});
  final _Filter value;
  final _Counts counts;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_Filter.all, '전체 ${counts.total}'),
      (_Filter.waiting, '등원 전 ${counts.waiting}'),
      (_Filter.inClass, '수업 중 ${counts.inClass}'),
      (_Filter.out, '하원 ${counts.out}'),
      (_Filter.absent, '결석 ${counts.absent}'),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (f, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(label), selected: value == f, onSelected: (_) => onChanged(f)),
            ),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.a, required this.onCheckIn, required this.onCheckOut, required this.onManual});

  final Attendance a;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback onManual;

  static final _hm = DateFormat('HH:mm');

  String get _detail {
    final parts = <String>[];
    if (a.checkInAt != null) parts.add('등원 ${_hm.format(a.checkInAt!)}');
    if (a.checkOutAt != null) parts.add('하원 ${_hm.format(a.checkOutAt!)}');
    if (a.nextDestinationName != null && a.status == AttendanceStatus.out) parts.add('→ ${a.nextDestinationName}');
    if (a.status == AttendanceStatus.absent && a.absenceReason != null) parts.add(a.absenceReason!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final action = switch (a.status) {
      AttendanceStatus.scheduled => FilledButton(
          onPressed: a.pending ? null : onCheckIn,
          style: FilledButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(84, 44)),
          child: const Text('등원'),
        ),
      AttendanceStatus.inClass => FilledButton(
          onPressed: a.pending ? null : onCheckOut,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(84, 44)),
          child: const Text('하원'),
        ),
      _ => null,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onLongPress: onManual,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(a.studentName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      StatusBadge(a.status, isLate: a.isLate, isEarlyLeave: a.isEarlyLeave),
                      if (a.pending) ...[
                        const SizedBox(width: 8),
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      ],
                    ]),
                    if (_detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(_detail, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (action != null) action,
              IconButton(icon: const Icon(Icons.more_vert, color: AppColors.muted), tooltip: '수동 변경', onPressed: onManual),
            ],
          ),
        ),
      ),
    );
  }
}
