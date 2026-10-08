import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';

/// Phase 2 ③ 교사앱 — CLS 건강 주의(알레르기) 배지, STF-004 교직원 출퇴근.

class HealthAlert {
  const HealthAlert({required this.studentId, required this.studentName, required this.allergies});
  final String studentId, studentName, allergies;

  factory HealthAlert.fromJson(Map<String, dynamic> j) =>
      HealthAlert(studentId: j['studentId'] as String, studentName: j['studentName'] as String, allergies: j['allergies'] as String);
}

class StaffRecord {
  const StaffRecord({required this.checkIn, this.checkOut, this.workedMinutes});
  final DateTime checkIn;
  final DateTime? checkOut;
  final int? workedMinutes;

  factory StaffRecord.fromJson(Map<String, dynamic> j) => StaffRecord(
        checkIn: DateTime.parse(j['checkIn'] as String).toLocal(),
        checkOut: j['checkOut'] == null ? null : DateTime.parse(j['checkOut'] as String).toLocal(),
        workedMinutes: j['workedMinutes'] as int?,
      );
}

final healthAlertsProvider = FutureProvider.autoDispose.family<List<HealthAlert>, String>((ref, classId) async {
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('classes/$classId/health-alerts');
  return r.data!.map((e) => HealthAlert.fromJson(e as Map<String, dynamic>)).toList();
});

final staffTodayProvider = FutureProvider.autoDispose<StaffRecord?>((ref) async {
  final r = await ref.watch(apiClientProvider).dio.get<Map<String, dynamic>>('staff-attendance/today');
  final rec = r.data!['record'];
  return rec == null ? null : StaffRecord.fromJson(rec as Map<String, dynamic>);
});

/// 반 출결 화면 상단 — 알레르기가 있는 원생이 있을 때만 보인다. 실패해도 출결 화면을 막지 않는다.
class HealthAlertBanner extends ConsumerWidget {
  const HealthAlertBanner({super.key, required this.classId});
  final String classId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(healthAlertsProvider(classId)).valueOrNull ?? const <HealthAlert>[];
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.error),
          SizedBox(width: 6),
          Text('알레르기 주의', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
        ]),
        const SizedBox(height: 6),
        for (final a in alerts) Text('${a.studentName} · ${a.allergies}', style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}

class StaffCheckInScreen extends ConsumerStatefulWidget {
  const StaffCheckInScreen({super.key});

  @override
  ConsumerState<StaffCheckInScreen> createState() => _StaffCheckInScreenState();
}

class _StaffCheckInScreenState extends ConsumerState<StaffCheckInScreen> {
  bool _busy = false;
  static final _hm = DateFormat('HH:mm');

  Future<void> _act(String path) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).dio.post<void>('staff-attendance/$path');
      ref.invalidate(staffTodayProvider);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e)), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(staffTodayProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('출퇴근')),
      body: today.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e), style: const TextStyle(color: AppColors.textSecondary))),
        data: (rec) {
          final done = rec?.checkOut != null;
          final status = rec == null
              ? '아직 출근 전입니다'
              : done
                  ? '출근 ${_hm.format(rec.checkIn)} · 퇴근 ${_hm.format(rec.checkOut!)}'
                  : '${_hm.format(rec.checkIn)} 출근 · 근무 중';
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${DateTime.now().month}월 ${DateTime.now().day}일', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: AppColors.textSecondary)),
              if (done && rec.workedMinutes != null) Text('근무 ${rec.workedMinutes! ~/ 60}시간 ${rec.workedMinutes! % 60}분'),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(onPressed: _busy || rec != null ? null : () => _act('check-in'), child: const Text('출근')),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(onPressed: _busy || rec == null || done ? null : () => _act('check-out'), child: const Text('퇴근')),
              ),
            ]),
          );
        },
      ),
    );
  }
}
