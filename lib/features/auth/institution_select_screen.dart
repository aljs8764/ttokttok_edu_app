import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';

/// 여러 기관에 소속된 교직원 — 오늘 일할 기관 선택 (스펙 7-8). 홈 화면 제목을 눌러 언제든 다시 바꾼다.
class InstitutionSelectScreen extends ConsumerWidget {
  const InstitutionSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final list = auth.user?.staffMemberships ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('기관 선택'),
        actions: [TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: const Text('로그아웃'))],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = list[i];
          final selected = m.institutionId == auth.institutionId;
          return Card(
            child: ListTile(
              title: Text(m.institutionName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(m.role.label),
              trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(authControllerProvider.notifier).selectInstitution(m.institutionId);
                // 홈에서 바꾸러 들어온 경우 바로 돌아간다 (처음 로그인 때는 라우터가 홈으로 보낸다)
                if (context.mounted && context.canPop()) context.pop();
              },
            ),
          );
        },
      ),
    );
  }
}
