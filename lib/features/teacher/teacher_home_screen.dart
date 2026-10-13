import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'models.dart';
import 'teacher_providers.dart';
import 'teacher_dashboard.dart';
import 'tutorial.dart';
import '../../core/i18n/i18n.dart';

/// 교사앱 홈 — 담당 반 목록. 오늘 수업 있는 반이 위로, 지금 수업 중인 반은 강조.
class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final classes = ref.watch(classesProvider);
    final now = DateTime.now();

    final classCount = classes.valueOrNull?.length;
    // 반별 오늘 출결 숫자 (DASH API classes[]: classroomId·present·scheduled·absent) — 없으면 숫자 칸을 숨긴다
    final todayCounts = {
      for (final c in ref.watch(teacherTodayProvider).valueOrNull?.classes ?? const <Map<String, dynamic>>[]) '${c['classroomId']}': c,
    };
    final multi = (auth.user?.staffMemberships.length ?? 0) > 1;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        // 디자인(T_Classes): 작은 줄 '기관 · 날짜' + 큰 제목 '내 담당 반 N개'. 여러 학원 소속이면 눌러서 학원을 바꾼다 (스펙 7-8)
        title: InkWell(
          onTap: multi ? () => context.push('/institution') : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    '${auth.membership?.institutionName ?? tr('똑똑')} · ${DateFormat(tr('M월 d일 (E)'), dateLocale()).format(now)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.plannedFg),
                  ),
                ),
                if (multi) const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.plannedFg),
              ]),
              const SizedBox(height: 2),
              Text(classCount == null ? tr('내 담당 반') : tr('내 담당 반 {0}개', [classCount]),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            ],
          ),
        ),
        actions: [const AttendanceTutorialGate(), _AccountMenu(auth: auth), const SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(teacherTodayProvider);
          return ref.refresh(classesProvider.future);
        },
        child: classes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(errorMessage(e), retry: () => ref.invalidate(classesProvider)),
          data: (list) {
            if (list.isEmpty) return _Message(tr('담당 반이 없습니다.\n원장님께 반 배정을 요청하세요.'));
            final sorted = [...list]..sort((a, b) {
                final ah = a.heldOn(now) ? 0 : 1, bh = b.heldOn(now) ? 0 : 1;
                return ah != bh ? ah - bh : a.startTime.compareTo(b.startTime);
              });
            // DASH-018~023: 맨 위 '오늘 할 일' 요약 → 누르면 교사 대시보드. 맨 아래 '알림장 쓰기'
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: sorted.length + 2,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i == 0) return const TodaySummaryCard();
                if (i == sorted.length + 1) {
                  return FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: () => context.push('/notices/new'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: Text(tr('알림장 쓰기')),
                  );
                }
                final c = sorted[i - 1];
                return _ClassCard(c: c, now: now, counts: todayCounts[c.id]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.c, required this.now, this.counts});

  final Classroom c;
  final DateTime now;
  final Map<String, dynamic>? counts;

  @override
  Widget build(BuildContext context) {
    final today = c.heldOn(now);
    final hm = DateFormat('HH:mm').format(now);
    final live = today && hm.compareTo(c.startTime) >= 0 && hm.compareTo(c.endTime) <= 0;
    final (state, chipBg, chipFg) = live
        ? (tr('수업 중'), AppColors.accent, AppColors.ink)
        : today
            ? (hm.compareTo(c.endTime) > 0 ? tr('끝남') : tr('예정'), AppColors.plannedBg, AppColors.plannedFg)
            : (tr('오늘 수업 없음'), AppColors.plannedBg, AppColors.plannedFg);
    final radius = BorderRadius.circular(AppRadius.card);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: live ? AppColors.ink : Colors.transparent, width: 2)),
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.push('/class/${c.id}?name=${Uri.encodeQueryComponent(c.name)}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
                  child: Text(state, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: chipFg)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('${c.startTime} – ${c.endTime}${c.headcount != null ? tr(' · 원생 {0}명', [c.headcount]) : ''}',
                  style: const TextStyle(fontSize: 13, color: AppColors.plannedFg)),
              if (today && counts != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  _Count(tr('등원'), counts!['present'], AppColors.checkInFg),
                  const SizedBox(width: 6),
                  _Count(tr('미등원'), counts!['scheduled'], AppColors.checkOutFg),
                  const SizedBox(width: 6),
                  _Count(tr('결석'), counts!['absent'], AppColors.ink),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);
  final String label;
  final Object? value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(10)),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label '),
              TextSpan(text: '${value ?? 0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            ]),
            style: const TextStyle(fontSize: 12, color: AppColors.plannedFg),
          ),
        ),
      );
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.auth});
  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multi = (auth.user?.staffMemberships.length ?? 0) > 1;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) {
        switch (v) {
          case 'inst':
            context.push('/institution');
          case 'work':
            context.push('/staff-attendance');
          case 'shuttle':
            context.push('/shuttle-drive');
          case 'consult':
            context.push('/consults');
          case 'community':
            context.push('/community');
          case 'social':
            context.push('/settings/social');
          case 'tutorial':
            showAttendanceTutorial(context);
          case 'pw':
            context.push('/settings/password');
          case 'logout':
            ref.read(authControllerProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text('${auth.user?.name ?? ''} · ${auth.membership?.role.label ?? ''}')),
        if (multi) PopupMenuItem(value: 'inst', child: Text(tr('기관 바꾸기'))),
        PopupMenuItem(value: 'work', child: Text(tr('출퇴근'))),
        PopupMenuItem(value: 'shuttle', child: Text(tr('셔틀 운행'))),
        PopupMenuItem(value: 'consult', child: Text(tr('상담 예약'))),
        PopupMenuItem(value: 'community', child: Text(tr('커뮤니티'))),
        PopupMenuItem(value: 'tutorial', child: Text(tr('출결 사용법 보기'))),
        PopupMenuItem(value: 'social', child: Text(tr('간편 로그인 연결'))),
        PopupMenuItem(value: 'pw', child: Text(tr('비밀번호 변경'))),
        PopupMenuItem(value: 'logout', child: Text(tr('로그아웃'))),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.retry});
  final String text;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => ListView(
        // RefreshIndicator 가 당겨지도록 스크롤 가능하게
        children: [
          const SizedBox(height: 120),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          if (retry != null) Center(child: TextButton(onPressed: retry, child: Text(tr('다시 시도')))),
        ],
      );
}
