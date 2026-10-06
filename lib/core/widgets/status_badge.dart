import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/teacher/models.dart';

/// IA 상태 5종(등원/하원/결석/지각/조퇴)을 상태 4개 + 플래그 2개에서 표시 (관리자 웹 attendanceLabel 과 같은 규칙)
({String label, Color color}) attendanceLabel(AttendanceStatus s, {bool isLate = false, bool isEarlyLeave = false}) {
  switch (s) {
    case AttendanceStatus.scheduled:
      return (label: '등원 전', color: AppColors.muted);
    case AttendanceStatus.absent:
      return (label: '결석', color: AppColors.error);
    case AttendanceStatus.inClass:
      return isLate ? (label: '등원(지각)', color: AppColors.warning) : (label: '등원', color: AppColors.success);
    case AttendanceStatus.out:
      if (isEarlyLeave) return (label: isLate ? '하원(지각·조퇴)' : '하원(조퇴)', color: AppColors.warning);
      return isLate ? (label: '하원(지각)', color: AppColors.warning) : (label: '하원', color: AppColors.info);
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
      decoration: BoxDecoration(color: l.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(l.label, style: TextStyle(color: l.color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
