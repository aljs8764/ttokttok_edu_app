import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'parent_providers.dart';
import '../../core/i18n/i18n.dart';

/// 자녀 선택 (전체 / 아이별, PAR-006). 아이 하나가 여러 기관에 다니면 그 기관 모두가 한 칩이다 (스펙 7-8).
/// 디자인(Main): 44px 둥근 버튼 + 이니셜 아바타, 선택 = Ink 채움
class ChildSelector extends ConsumerWidget {
  const ChildSelector({super.key});

  static const height = 60.0;
  static const _avatarColors = [AppColors.accent, Color(0xFFBFD3FF), Color(0xFFFFD3B8), Color(0xFFC9EBD6)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider).valueOrNull ?? const [];
    final selected = ref.watch(selectedChildProvider);
    if (children.isEmpty) return const SizedBox(height: height);

    final multi = children.length > 1;
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        children: [
          if (multi)
            _ChildButton(
              label: tr('전체'),
              selected: selected == null,
              onTap: () => ref.read(selectedChildProvider.notifier).state = null,
            ),
          for (var i = 0; i < children.length; i++)
            _ChildButton(
              initial: children[i].name.isEmpty ? '?' : children[i].name.characters.first,
              avatar: _avatarColors[i % _avatarColors.length],
              label: children[i].name,
              sub: children[i].enrollments.length > 2 ? tr('기관 {0}곳', [children[i].enrollments.length]) : children[i].institutionsLabel,
              selected: multi ? selected == children[i].childId : true,
              onTap: multi ? () => ref.read(selectedChildProvider.notifier).state = children[i].childId : null,
            ),
        ],
      ),
    );
  }
}

class _ChildButton extends StatelessWidget {
  const _ChildButton({required this.label, required this.selected, this.onTap, this.initial, this.avatar, this.sub});

  final String label;
  final String? initial;
  final Color? avatar;
  final String? sub;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.ink : Colors.white,
          shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.inputBorder)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(initial != null ? 8 : 16, 0, 16, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (initial != null) ...[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: avatar, shape: BoxShape.circle),
                    child: Text(initial!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                if (sub != null && sub!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      sub!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg.withValues(alpha: 0.75)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
