import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'parent_providers.dart';
import '../../core/i18n/i18n.dart';

/// 스펙 7-8 "같은 아이인가요?" — 한 아이가 여러 학원에 다니면 학원마다 따로 등록돼 아이가 둘로 보인다.
/// 보호자가 확인하면 하나로 합친다 (서버는 이름·생일로 자동으로 합치지 않는다).
class MergeSuggestionBanner extends ConsumerStatefulWidget {
  const MergeSuggestionBanner({super.key});

  @override
  ConsumerState<MergeSuggestionBanner> createState() => _MergeSuggestionBannerState();
}

class _MergeSuggestionBannerState extends ConsumerState<MergeSuggestionBanner> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(mergeSuggestionsProvider).valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final m = list.first;
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('{0}, 같은 아이인가요?', [m.name]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              tr('{0}에 같은 이름·생일로 등록돼 있어요. 같은 아이면 하나로 합쳐 한눈에 보고, 학생앱 하나로 모든 곳에서 출석할 수 있어요.', [m.institutionNames.join(', ')]),
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => ref.read(mergeSuggestionsProvider.notifier).dismiss(m),
                  child: Text(tr('다른 아이예요')),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await ref.read(mergeSuggestionsProvider.notifier).merge(m);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('{0}(으)로 합쳤어요', [m.name]))));
                            }
                          } catch (e) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: Text(tr('같은 아이예요')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
