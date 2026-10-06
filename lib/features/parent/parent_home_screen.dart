import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';

/// 학부모앱 자리 — 다음 단계에서 PAR-001 타임라인·PAR-004 알림장함·PAR-005 행사 응답·PAR-003 스케줄을 채운다.
/// 지금은 로그인과 자녀 연결(/me/children)만 확인할 수 있다.
final _childrenProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>('me/children', options: _noInst);
    return r.data!.cast<Map<String, dynamic>>();
  } catch (e) {
    throw ApiException.from(e);
  }
});

final _noInst = Options(extra: {'noInstitution': true});

class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(_childrenProvider);
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('똑똑'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => ref.read(authControllerProvider.notifier).logout())],
      ),
      body: children.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${user?.name ?? ''} 님', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Text('연결된 자녀가 없습니다. 학원에 등록된 보호자 번호와 가입한 번호가 같은지 확인해 주세요.',
                  style: TextStyle(color: AppColors.textSecondary)),
            for (final c in list)
              Card(child: ListTile(title: Text(c['name'] as String), subtitle: Text(c['institutionName'] as String))),
            const SizedBox(height: 24),
            const Text('타임라인·알림장·행사 화면은 준비 중입니다.', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
