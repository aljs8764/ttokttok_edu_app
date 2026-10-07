import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'merge_banner.dart';
import 'models.dart';
import 'parent_providers.dart';
import 'parent_repository.dart';
import 'student_device_sheet.dart';

/// 더보기 — 아이별 다니는 기관(스펙 7-8)·학생앱 연결(PAR-007)·이름, 비밀번호 변경, 로그아웃
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final children = ref.watch(childrenProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${user?.name ?? ''} 님', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        const MergeSuggestionBanner(),
        const Text('우리 아이', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        ...children.when(
          loading: () => [const LinearProgressIndicator()],
          error: (_, __) => [const Text('불러오지 못했습니다')],
          data: (list) => list.isEmpty
              ? [
                  const Text(
                    '아직 연결된 자녀가 없습니다. 학원에 등록된 보호자 번호로 가입했는지 확인하거나, 학원에서 받은 초대 링크로 자녀 정보를 보내 주세요.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                  ),
                ]
              : [for (final c in list) _ChildCard(child: c)],
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('비밀번호 변경'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/password'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('로그아웃'),
              onTap: () => ref.read(authControllerProvider.notifier).logout(),
            ),
          ]),
        ),
      ],
    );
  }
}

/// 아이 한 명 — 다니는 학원·학교 목록, 학생앱 연결, 이름 바꾸기, 잘못 합친 기관 나누기
class _ChildCard extends ConsumerWidget {
  const _ChildCard({required this.child});
  final Child child;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: child.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이름 바꾸기'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(helperText: '이 앱에서만 바뀌어요. 학원에 등록된 이름은 그대로예요.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('저장')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == child.name) return;
    await _run(context, ref, () => ref.read(parentRepositoryProvider).renameChild(child.childId, name));
  }

  Future<void> _split(BuildContext context, WidgetRef ref, Enrollment e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('다른 아이로 나누기'),
        content: Text('${e.institutionName}의 ${e.studentName}을(를) ${child.name}와(과) 다른 아이로 나눕니다. 학생앱 연결은 ${child.name}에 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나누기')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    await _run(context, ref, () => ref.read(parentRepositoryProvider).splitChild(child.childId, e.studentId));
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<Object?> Function() f) async {
    try {
      await f();
      ref.read(selectedChildProvider.notifier).state = null;
      ref.invalidate(childrenProvider);
    } catch (err) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(err))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multi = child.enrollments.length > 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const CircleAvatar(child: Icon(Icons.child_care)),
              const SizedBox(width: 12),
              Expanded(child: Text(child.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'rename' ? _rename(context, ref) : null,
                itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('이름 바꾸기'))],
              ),
            ]),
            const SizedBox(height: 4),
            for (final e in child.enrollments)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 4, right: 4),
                leading: Icon(e.institutionType == 'SCHOOL' ? Icons.school_outlined : Icons.apartment_outlined, size: 20),
                title: Text(e.institutionName),
                subtitle: Text([
                  e.typeLabel,
                  if (e.studentName != child.name) '등록 이름 ${e.studentName}',
                  if (e.status == 'PAUSED') '휴원',
                  if (e.status == 'WITHDRAWN') '퇴원',
                ].join(' · ')),
                trailing: multi
                    ? IconButton(
                        tooltip: '다른 아이로 나누기',
                        icon: const Icon(Icons.call_split, size: 20),
                        onPressed: () => _split(context, ref, e),
                      )
                    : null,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('학생앱 연결'),
                onPressed: () => showStudentDeviceSheet(context, child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
