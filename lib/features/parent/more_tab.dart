import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_controller.dart';
import 'parent_providers.dart';

/// 더보기 — 연결된 자녀, 비밀번호 변경, 로그아웃
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
        const Text('연결된 자녀', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
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
              : [
                  for (final c in list)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.child_care)),
                        title: Text(c.name),
                        subtitle: Text(c.institutionName),
                      ),
                    ),
                ],
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
