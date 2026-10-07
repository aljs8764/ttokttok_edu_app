import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'parent_providers.dart';

/// 자녀 선택 칩 (전체 / 아이별). 아이 하나가 여러 기관에 다니면 그 기관 모두가 한 칩이다 (스펙 7-8).
class ChildSelector extends ConsumerWidget {
  const ChildSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider).valueOrNull ?? const [];
    final selected = ref.watch(selectedChildProvider);
    if (children.isEmpty) return const SizedBox(height: 52);

    final multi = children.length > 1;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          if (multi)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('전체'),
                selected: selected == null,
                onSelected: (_) => ref.read(selectedChildProvider.notifier).state = null,
              ),
            ),
          for (final c in children)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.enrollments.length > 2 ? '${c.name} · 기관 ${c.enrollments.length}곳' : '${c.name} · ${c.institutionsLabel}'),
                selected: multi ? selected == c.childId : true,
                onSelected: multi ? (_) => ref.read(selectedChildProvider.notifier).state = c.childId : null,
              ),
            ),
        ],
      ),
    );
  }
}
