import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';

/// 똑똑 로고 마크 — Accent 바탕의 '똑' (디자인 공통)
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(size * 0.31)),
        child: Text(tr('똑'), style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1)),
      );
}
