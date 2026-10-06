import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'models.dart';
import 'teacher_providers.dart';

/// 교사앱 홈 — 담당 반 목록. 오늘 수업 있는 반이 위로, 지금 수업 중인 반은 강조.
class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final classes = ref.watch(classesProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(auth.membership?.institutionName ?? '똑똑'),
            Text(DateFormat('M월 d일 (E)', 'ko_KR').format(now), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [_AccountMenu(auth: auth)],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(classesProvider.future),
        child: classes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(errorMessage(e), retry: () => ref.invalidate(classesProvider)),
          data: (list) {
            if (list.isEmpty) return const _Message('담당 반이 없습니다.\n원장님께 반 배정을 요청하세요.');
            final sorted = [...list]..sort((a, b) {
                final ah = a.heldOn(now) ? 0 : 1, bh = b.heldOn(now) ? 0 : 1;
                return ah != bh ? ah - bh : a.startTime.compareTo(b.startTime);
              });
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ClassCard(c: sorted[i], now: now),
            );
          },
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.c, required this.now});

  final Classroom c;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = c.heldOn(now);
    final hm = DateFormat('HH:mm').format(now);
    final live = today && hm.compareTo(c.startTime) >= 0 && hm.compareTo(c.endTime) <= 0;
    return Card(
      shape: live
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.accent, width: 1.5))
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/class/${c.id}?name=${Uri.encodeQueryComponent(c.name)}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      if (live) ...[
                        const SizedBox(width: 8),
                        const _Pill('수업 중', AppColors.accent),
                      ] else if (!today) ...[
                        const SizedBox(width: 8),
                        const _Pill('오늘 수업 없음', AppColors.muted),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text('${c.startTime}~${c.endTime}${c.headcount != null ? ' · ${c.headcount}명' : ''}',
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
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
          case 'pw':
            context.push('/settings/password');
          case 'logout':
            ref.read(authControllerProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text('${auth.user?.name ?? ''} · ${auth.membership?.role.label ?? ''}')),
        if (multi) const PopupMenuItem(value: 'inst', child: Text('기관 바꾸기')),
        const PopupMenuItem(value: 'pw', child: Text('비밀번호 변경')),
        const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
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
          if (retry != null) Center(child: TextButton(onPressed: retry, child: const Text('다시 시도'))),
        ],
      );
}
