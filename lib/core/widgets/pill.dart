import 'package:flutter/material.dart';

/// 작은 상태 알약 (예약·발송·취소 등). 글자색을 받아 옅은 배경을 만든다.
/// 디자인 토큰 배경을 그대로 쓰려면 [Pill.tone] 을 쓴다.
class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key}) : background = null;

  /// 배경·글자색을 토큰 쌍으로 지정 (예: AppColors.checkInBg / checkInFg)
  const Pill.tone(this.text, {required Color bg, required Color fg, super.key})
      : color = fg,
        background = bg;

  final String text;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: background ?? color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}
