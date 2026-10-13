import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/teacher/models.dart';
import '../i18n/i18n.dart';

/// IA 상태 5종(등원/하원/결석/지각/조퇴)을 상태 4개 + 플래그 2개에서 표시 (관리자 웹 attendanceLabel 과 같은 규칙)
/// 색은 앱 디자인 토큰: 등원 파랑, 하원 주황, 예정 회색, 결석 빨강, 지각·조퇴는 라벨로 구분.
({String label, Color color, Color bg}) attendanceLabel(AttendanceStatus s, {bool isLate = false, bool isEarlyLeave = false}) {
  const inn = (AppColors.checkInFg, AppColors.checkInBg);
  const out = (AppColors.checkOutFg, AppColors.checkOutBg);
  switch (s) {
    case AttendanceStatus.scheduled:
      return (label: tr('등원 전'), color: AppColors.plannedFg, bg: AppColors.plannedBg);
    case AttendanceStatus.absent:
      return (label: tr('결석'), color: AppColors.dangerFg, bg: AppColors.dangerBg);
    case AttendanceStatus.inClass:
      return (label: isLate ? tr('등원(지각)') : tr('등원'), color: inn.$1, bg: inn.$2);
    case AttendanceStatus.out:
      final label = isEarlyLeave
          ? (isLate ? tr('하원(지각·조퇴)') : tr('하원(조퇴)'))
          : (isLate ? tr('하원(지각)') : tr('하원'));
      return (label: label, color: out.$1, bg: out.$2);
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.isLate = false, this.isEarlyLeave = false});

  final AttendanceStatus status;
  final bool isLate;
  final bool isEarlyLeave;

  @override
  Widget build(BuildContext context) {
    final l = attendanceLabel(status, isLate: isLate, isEarlyLeave: isEarlyLeave);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: l.bg, borderRadius: BorderRadius.circular(6)),
      child: Text(l.label, style: TextStyle(color: l.color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
