import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/i18n/i18n.dart';

/// ONB-004 교사앱 첫 실행 튜토리얼 — 원터치 출결을 3단계로 안내한다.
/// 진행 상태는 기기에 저장(다시 보기는 메뉴 > 사용법 보기).
const _doneKey = 'tutorial.attendance.v1';

class _Step {
  const _Step(this.icon, this.title, this.body);
  final IconData icon;
  final String title, body;
}

const _steps = [
  _Step(Icons.class_outlined, '1. 반을 고르세요', '홈에는 담당 반만 보여요. 오늘 수업이 있는 반이 위에, 지금 수업 중인 반은 강조돼 있어요.'),
  _Step(Icons.touch_app_outlined, '2. [출석]을 한 번 누르세요', '아이 카드의 [출석]을 누르면 바로 등원 처리되고, 학부모님께 알림이 갑니다.'),
  _Step(Icons.directions_walk_outlined, '3. [하원] → 다음 목적지', '[하원]을 누르고 집·다른 학원·셔틀 중 다음 목적지를 고르면, 학부모님이 아이가 어디로 가는지 알 수 있어요.'),
];

Future<void> showAttendanceTutorial(BuildContext context) async {
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _TutorialDialog());
  try {
    (await SharedPreferences.getInstance()).setBool(_doneKey, true);
  } catch (_) {}
}

/// 홈 화면에 넣어 두면 처음 한 번만 튜토리얼을 띄운다 (화면에는 아무것도 그리지 않음)
class AttendanceTutorialGate extends StatefulWidget {
  const AttendanceTutorialGate({super.key});

  @override
  State<AttendanceTutorialGate> createState() => _AttendanceTutorialGateState();
}

class _AttendanceTutorialGateState extends State<AttendanceTutorialGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_doneKey) == true || !mounted) return;
        await showAttendanceTutorial(context);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _TutorialDialog extends StatefulWidget {
  const _TutorialDialog();

  @override
  State<_TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<_TutorialDialog> {
  final _page = PageController();
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _steps.length - 1;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('원터치 출결 사용법'), style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: _page,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) {
                final s = _steps[i];
                return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircleAvatar(radius: 32, backgroundColor: AppColors.primary.withValues(alpha: 0.08), child: Icon(s.icon, size: 32, color: AppColors.primary)),
                  const SizedBox(height: 16),
                  Text(tr(s.title), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(tr(s.body), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
                ]);
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _steps.length; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(shape: BoxShape.circle, color: i == _i ? AppColors.primary : AppColors.muted.withValues(alpha: 0.4)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('건너뛰기'))),
            const Spacer(),
            FilledButton(
              onPressed: () => last ? Navigator.pop(context) : _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
              child: Text(last ? tr('시작하기') : tr('다음')),
            ),
          ]),
        ]),
      ),
    );
  }
}
