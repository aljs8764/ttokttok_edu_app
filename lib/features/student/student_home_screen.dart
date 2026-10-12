import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/status_badge.dart';
import 'student_api.dart';
import '../../core/i18n/i18n.dart';

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
        title: Text(tr('연결 해제')),
        content: Text(tr('이 휴대폰의 연결을 끊습니다. 다시 쓰려면 부모님께 새 코드를 받아야 해요.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('취소'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('해제'))),
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
        title: Text(tr('똑똑 출석')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _confirmLogout(),
            itemBuilder: (_) => [PopupMenuItem(value: 'logout', child: Text(tr('이 기기 연결 해제')))],
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
            Center(child: TextButton(onPressed: () => ref.invalidate(studentHomeProvider), child: Text(tr('다시 시도')))),
          ]),
          data: (h) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(tr('{0} 안녕하세요', [h.info.studentName]), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(DateFormat(tr('M월 d일 (E)'), dateLocale()).format(DateTime.now()), style: const TextStyle(color: AppColors.textSecondary)),
              if (h.info.institutionNames.isNotEmpty)
                Text(h.info.institutionName, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 24),
              SizedBox(
                height: 120,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary, textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  icon: const Icon(Icons.qr_code_scanner, size: 40),
                  label: Text(tr('QR 출석')),
                  onPressed: () async {
                    await context.push('/scan');
                    ref.invalidate(studentHomeProvider);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(tr('다니는 학원 어디서든 입구 QR 을 찍으면 도착·출발이 부모님께 알림으로 가요.'),
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 28),
              Text(tr('오늘 수업'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              if (h.today.isEmpty) Text(tr('오늘은 수업이 없어요'), style: TextStyle(color: AppColors.textSecondary)),
              for (final c in h.today)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(c.classroomName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${h.info.institutionNames.length > 1 ? '${c.institutionName} · ' : ''}${c.startTime}~${c.endTime}${_times(c)}'),
                      trailing: c.attendance == null
                          ? Text(tr('등원 전'), style: TextStyle(color: AppColors.muted))
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
      if (a.checkInAt != null) tr('도착 {0}', [f.format(a.checkInAt!)]),
      if (a.checkOutAt != null) tr('출발 {0}', [f.format(a.checkOutAt!)]),
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }
}
