import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'models.dart';
import 'parent_providers.dart';
import 'parent_repository.dart';

/// SET-005 학부모 약관 재동의 — 개정되어 아직 동의하지 않은 약관이 있으면 띄운다.
/// 필수 약관이 남아 있으면 닫을 수 없다(동의 또는 로그아웃).
Future<void> showTermsGateIfNeeded(BuildContext context, WidgetRef ref) async {
  List<Terms> pending;
  try {
    pending = await ref.read(pendingTermsProvider.future);
  } catch (_) {
    return; // 조회 실패면 다음 실행 때 다시
  }
  if (pending.isEmpty || !context.mounted) return;
  final blocking = pending.any((t) => t.required);
  await showDialog<void>(
    context: context,
    barrierDismissible: !blocking,
    builder: (_) => PopScope(canPop: !blocking, child: _TermsDialog(pending: pending, blocking: blocking)),
  );
}

class _TermsDialog extends ConsumerStatefulWidget {
  const _TermsDialog({required this.pending, required this.blocking});
  final List<Terms> pending;
  final bool blocking;

  @override
  ConsumerState<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends ConsumerState<_TermsDialog> {
  final _checked = <String>{};
  bool _busy = false;
  String? _error;

  bool get _allRequired => widget.pending.where((t) => t.required).every((t) => _checked.contains(t.id));

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(parentRepositoryProvider).agreeTerms(_checked.toList());
      ref.invalidate(pendingTermsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('약관이 개정되었습니다'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              widget.blocking ? '계속 이용하려면 필수 약관에 동의해 주세요.' : '선택 약관은 동의하지 않아도 이용할 수 있습니다.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final t in widget.pending) TermsCheckTile(terms: t, checked: _checked.contains(t.id), onChanged: (v) => setState(() => v ? _checked.add(t.id) : _checked.remove(t.id))),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
        ),
      ),
      actions: [
        if (widget.blocking)
          TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: const Text('로그아웃'))
        else
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('나중에')),
        FilledButton(onPressed: _allRequired && _checked.isNotEmpty && !_busy ? _agree : null, child: const Text('동의')),
      ],
    );
  }
}

/// 약관 한 줄 — 체크 + 본문 보기 (가입 화면에서도 쓴다)
class TermsCheckTile extends StatelessWidget {
  const TermsCheckTile({super.key, required this.terms, required this.checked, required this.onChanged});
  final Terms terms;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Checkbox(value: checked, onChanged: (v) => onChanged(v ?? false)),
      Expanded(
        child: GestureDetector(
          onTap: () => onChanged(!checked),
          child: Text('[${terms.required ? '필수' : '선택'}] ${terms.title}'),
        ),
      ),
      TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(terms.title),
            content: SingleChildScrollView(child: Text(terms.body)),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기'))],
          ),
        ),
        child: const Text('보기'),
      ),
    ]);
  }
}
