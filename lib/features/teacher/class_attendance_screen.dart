import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/realtime/stomp_service.dart';
import '../../core/widgets/status_badge.dart';
import 'attendance_queue.dart';
import 'models.dart';
import 'ops_screens.dart';
import 'sheets.dart';
import 'teacher_providers.dart';
import '../../core/i18n/i18n.dart';

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
      // 밀린 오프라인 큐를 먼저 보내고(성공하면 서버 값으로 다시 읽힘), 아니면 그냥 다시 읽는다
      final queue = ref.read(attendanceQueueProvider.notifier);
      if (ref.read(attendanceQueueProvider).isNotEmpty) {
        queue.flush().then((sent) {
          if (sent == 0 && mounted) _ctrl.reload();
        });
      } else {
        _ctrl.reload();
      }
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
      if (mounted) _toast(tr('{0} 등원 실패: {1}', [a.studentName, errorMessage(e)]), error: true);
    }
  }

  Future<void> _checkOut(Attendance a) async {
    final dest = await showDestinationSheet(context, studentName: a.studentName);
    if (dest == null) return;
    HapticFeedback.lightImpact();
    try {
      await _ctrl.checkOut(a, dest);
    } catch (e) {
      if (mounted) _toast(tr('{0} 하원 실패: {1}', [a.studentName, errorMessage(e)]), error: true);
    }
  }

  Future<void> _flushNow() async {
    final sent = await ref.read(attendanceQueueProvider.notifier).flush();
    if (!mounted) return;
    _toast(sent > 0 ? tr('{0}건을 보냈습니다', [sent]) : tr('아직 보내지 못했습니다. 네트워크를 확인하세요'));
  }

  Future<void> _manual(Attendance a) async {
    if (a.dayId == null) {
      _toast(tr('오늘 출결 기록이 아직 없어 바꿀 수 없습니다. 등원을 먼저 눌러 주세요'));
      return;
    }
    final changed = await showStatusChangeSheet(context, a, (to, reason, isLate, isEarlyLeave) {
      return _ctrl.changeStatus(a, to, reason, isLate: isLate, isEarlyLeave: isEarlyLeave);
    });
    if (changed == true && mounted) _toast(tr('{0} 출결을 바꿨습니다', [a.studentName]));
  }

  /// 미등원 전원 출석 — 한 명씩 원터치와 같은 경로(낙관적 반영 + 오프라인 큐)로 보낸다
  Future<void> _checkInAll(List<Attendance> list) async {
    final targets = list.where((a) => a.status == AttendanceStatus.scheduled && !a.pending).toList();
    if (targets.isEmpty) return;
    final ok = await _confirm(tr('미등원 {0}명을 모두 출석 처리할까요?\n보호자에게 등원 알림이 갑니다.', [targets.length]), tr('전원 출석'));
    if (ok != true) return;
    HapticFeedback.lightImpact();
    var failed = 0;
    for (final a in targets) {
      try {
        await _ctrl.checkIn(a);
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      _toast(failed == 0
          ? tr('{0}명 출석 · 보호자에게 알림을 보냈어요', [targets.length])
          : tr('{0}명 중 {1}명은 처리하지 못했습니다', [targets.length, failed]), error: failed > 0);
    }
  }

  /// 일괄 하원 — 수업 중인 원생을 같은 목적지로
  Future<void> _checkOutAll(List<Attendance> list) async {
    final targets = list.where((a) => a.status == AttendanceStatus.inClass && !a.pending).toList();
    if (targets.isEmpty) return;
    final dest = await showDestinationSheet(context, studentName: tr('수업 중 {0}명', [targets.length]), group: true);
    if (dest == null) return;
    HapticFeedback.lightImpact();
    var failed = 0;
    for (final a in targets) {
      try {
        await _ctrl.checkOut(a, dest);
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      _toast(failed == 0
          ? tr('{0}명 하원 → {1} · 보호자에게 알림을 보냈어요', [targets.length, dest.name])
          : tr('{0}명 중 {1}명은 처리하지 못했습니다', [targets.length, failed]), error: failed > 0);
    }
  }

  Future<bool?> _confirm(String text, String action) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('취소'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(classAttendanceProvider(widget.classId));
    final connected = ref.watch(stompServiceProvider).connected;

    // 실시간 — 이 반 토픽
    ref.listen(realtimeProvider('/topic/class.${widget.classId}'), (_, next) {
      final m = next.valueOrNull;
      if (m != null) _ctrl.applyRealtime(m);
    });

    // 오프라인 큐에서 서버가 거절한 항목 안내
    ref.listen(queueFailuresProvider, (_, next) {
      if (next.isEmpty) return;
      _toast(tr('전송하지 못한 항목: {0}', [next.join(' / ')]), error: true);
      Future.microtask(() => ref.read(queueFailuresProvider.notifier).state = const []);
    });
    final queued = ref.watch(attendanceQueueProvider).where((q) => q.classroomId == widget.classId).length;

    // 자정을 넘겨 화면을 켜 두었으면 새 날짜로
    if (!DateUtils.isSameDay(_loadedDay, DateTime.now())) {
      _loadedDay = DateTime.now();
      Future.microtask(_ctrl.reload);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('{0} 출결', [widget.className]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(DateFormat(tr('M월 d일 (E)'), dateLocale()).format(DateTime.now()),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary)),
        ]),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: connected,
            builder: (_, on, __) => Tooltip(
              message: on ? tr('실시간 연결됨') : tr('실시간 연결 대기 중 (당겨서 새로고침)'),
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
            TextButton(onPressed: _ctrl.reload, child: Text(tr('다시 시도'))),
          ]),
        ),
        data: (list) {
          final counts = _Counts.of(list);
          final shown = list.where(_match).toList();
          return RefreshIndicator(
            onRefresh: _ctrl.reload,
            child: CustomScrollView(
              slivers: [
                if (queued > 0) SliverToBoxAdapter(child: _QueueBanner(count: queued, onFlush: _flushNow)),
                SliverToBoxAdapter(child: HealthAlertBanner(classId: widget.classId)),
                SliverToBoxAdapter(child: _Summary(counts: counts)),
                SliverToBoxAdapter(child: _FilterBar(value: _filter, counts: counts, onChanged: (f) => setState(() => _filter = f))),
                if (list.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(tr('오늘 출결 대상 원생이 없습니다'), style: TextStyle(color: AppColors.textSecondary))),
                  )
                else
                  // 디자인(T_Attendance): 흰 카드 하나 안에 원생 줄 + 구분선
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    sliver: DecoratedSliver(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
                      sliver: SliverList.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.plannedBg),
                        itemBuilder: (_, i) => _StudentRow(
                          a: shown[i],
                          onCheckIn: () => _checkIn(shown[i]),
                          onCheckOut: () => _checkOut(shown[i]),
                          onManual: () => _manual(shown[i]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      // 미등원 전원 출석 · 일괄 하원
      bottomNavigationBar: rows.valueOrNull == null || rows.valueOrNull!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: rows.valueOrNull!.any((a) => a.status == AttendanceStatus.scheduled) ? () => _checkInAll(rows.valueOrNull!) : null,
                      child: Text(tr('미등원 전원 출석')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: rows.valueOrNull!.any((a) => a.status == AttendanceStatus.inClass) ? () => _checkOutAll(rows.valueOrNull!) : null,
                      child: Text(tr('일괄 하원')),
                    ),
                  ),
                ]),
              ),
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

/// 오프라인 큐에 쌓인 건이 있을 때 — 자동 전송을 기다리거나 바로 보내 본다
class _QueueBanner extends StatelessWidget {
  const _QueueBanner({required this.count, required this.onFlush});
  final int count;
  final VoidCallback onFlush;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(color: AppColors.noticeBg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.cloud_off, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('전송 대기 {0}건 · 연결되면 자동으로 보냅니다', [count]), style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onFlush, child: Text(tr('지금 보내기'))),
        ]),
      );
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
    // 디자인: 미등원 · 등원 · 하원 · 결석 4칸 (지각은 아래 줄)
    Widget cell(String label, int n, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          cell(tr('미등원'), counts.waiting, AppColors.checkOutFg),
          const SizedBox(width: 6),
          cell(tr('등원'), counts.inClass, AppColors.checkInFg),
          const SizedBox(width: 6),
          cell(tr('하원'), counts.out, AppColors.ink),
          const SizedBox(width: 6),
          cell(tr('결석'), counts.absent, AppColors.plannedFg),
        ]),
        if (counts.late > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(tr('지각 {0}명', [counts.late]), style: const TextStyle(fontSize: 12, color: AppColors.checkOutFg, fontWeight: FontWeight.w600)),
          ),
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
      (_Filter.all, tr('전체 {0}', [counts.total])),
      (_Filter.waiting, tr('등원 전 {0}', [counts.waiting])),
      (_Filter.inClass, tr('수업 중 {0}', [counts.inClass])),
      (_Filter.out, tr('하원 {0}', [counts.out])),
      (_Filter.absent, tr('결석 {0}', [counts.absent])),
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
    if (a.checkInAt != null) parts.add(tr('등원 {0}', [_hm.format(a.checkInAt!)]));
    if (a.checkOutAt != null) parts.add(tr('하원 {0}', [_hm.format(a.checkOutAt!)]));
    if (a.nextDestinationName != null && a.status == AttendanceStatus.out) parts.add('→ ${a.nextDestinationName}');
    if (a.queued) parts.add(tr('전송 대기'));
    if (a.status == AttendanceStatus.absent && a.absenceReason != null) parts.add(a.absenceReason!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // [출석] 파랑 채움 / [하원] 주황 테두리 / 처리 끝난 줄은 글자로만
    final action = switch (a.status) {
      AttendanceStatus.scheduled => FilledButton(
          onPressed: a.pending ? null : onCheckIn,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.checkInFg,
            minimumSize: const Size(72, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          child: Text(tr('출석')),
        ),
      AttendanceStatus.inClass => OutlinedButton(
          onPressed: a.pending ? null : onCheckOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.checkOutFg,
            side: const BorderSide(color: AppColors.checkOutButton, width: 2),
            minimumSize: const Size(72, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          child: Text(tr('하원')),
        ),
      AttendanceStatus.out => SizedBox(
          width: 72,
          child: Text(tr('하원 완료'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7487))),
        ),
      AttendanceStatus.absent => SizedBox(
          width: 72,
          child: Text(tr('결석'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7487))),
        ),
    };
    final initial = a.studentName.length > 1 ? a.studentName.characters.elementAt(1) : a.studentName.characters.firstOrNull ?? '?';

    return InkWell(
      onLongPress: onManual,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.plannedBg, shape: BoxShape.circle),
                child: Text(initial, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.plannedFg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(a.studentName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      StatusBadge(a.status, isLate: a.isLate, isEarlyLeave: a.isEarlyLeave),
                      if (a.queued) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.cloud_off, size: 14, color: AppColors.warning),
                      ],
                      if (a.pending) ...[
                        const SizedBox(width: 6),
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(_detail.isEmpty ? tr('미등원') : _detail, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              action,
              IconButton(icon: const Icon(Icons.more_vert, color: AppColors.muted), tooltip: tr('수동 변경'), onPressed: onManual),
            ],
          ),
        ),
      ),
    );
  }
}
