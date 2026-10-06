import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/status_badge.dart';
import 'student_api.dart';

/// STD-002 학생앱 홈 — 오늘 수업과 출결, 큰 "QR 출석" 버튼.
class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> with WidgetsBindingObserver {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(studentHomeProvider);
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('연결 해제'),
        content: const Text('이 휴대폰의 연결을 끊습니다. 다시 쓰려면 부모님께 새 코드를 받아야 해요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('해제')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(studentApiProvider).logout();
    ref.read(studentLinkedProvider.notifier).set(false);
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(studentHomeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(home.valueOrNull?.info.institutionName ?? '똑똑 출석'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _confirmLogout(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'logout', child: Text('이 기기 연결 해제'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(studentHomeProvider.future),
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(errorMessage(e), style: const TextStyle(color: AppColors.textSecondary))),
            Center(child: TextButton(onPressed: () => ref.invalidate(studentHomeProvider), child: const Text('다시 시도'))),
          ]),
          data: (h) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('${h.info.studentName} 안녕하세요', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(DateFormat('M월 d일 (E)', 'ko_KR').format(DateTime.now()), style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              SizedBox(
                height: 120,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary, textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  icon: const Icon(Icons.qr_code_scanner, size: 40),
                  label: const Text('QR 출석'),
                  onPressed: () async {
                    await context.push('/scan');
                    ref.invalidate(studentHomeProvider);
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text('학원 입구에 붙은 QR 을 찍으면 도착·출발이 부모님께 알림으로 가요.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 28),
              const Text('오늘 수업', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              if (h.today.isEmpty) const Text('오늘은 수업이 없어요', style: TextStyle(color: AppColors.textSecondary)),
              for (final c in h.today)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(c.classroomName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${c.startTime}~${c.endTime}${_times(c)}'),
                      trailing: c.attendance == null
                          ? const Text('등원 전', style: TextStyle(color: AppColors.muted))
                          : StatusBadge(c.attendance!.status, isLate: c.attendance!.isLate, isEarlyLeave: c.attendance!.isEarlyLeave),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _times(TodayClass c) {
    final a = c.attendance;
    if (a == null) return '';
    final f = DateFormat('HH:mm');
    final parts = [
      if (a.checkInAt != null) '도착 ${f.format(a.checkInAt!)}',
      if (a.checkOutAt != null) '출발 ${f.format(a.checkOutAt!)}',
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }
}
