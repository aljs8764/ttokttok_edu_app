import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'parent_providers.dart';

/// 자녀 선택 칩 (전체 / 자녀별). 자녀가 한 명이면 이름만 보여 준다.
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
                label: Text(multi ? '${c.name} · ${c.institutionName}' : '${c.name} · ${c.institutionName}'),
                selected: multi ? selected == c.studentId : true,
                onSelected: multi ? (_) => ref.read(selectedChildProvider.notifier).state = c.studentId : null,
              ),
            ),
        ],
      ),
    );
  }
}
