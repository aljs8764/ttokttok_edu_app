import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'models.dart';
import 'parent_providers.dart';
import 'parent_repository.dart';

/// 행사 상세 + 자녀별 참석 응답 (PAR-005). 마감 전까지는 바꿀 수 있다.
Future<void> showRsvpSheet(BuildContext context, ParentEvent e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _RsvpSheet(event: e),
    ),
  );
}

class RsvpChip extends StatelessWidget {
  const RsvpChip(this.c, {super.key});
  final ChildRsvp c;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (c.answer) {
      'ATTEND' => ('참석', AppColors.success),
      'ABSENT' => ('불참', AppColors.error),
      _ => ('미응답', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text('${c.name} $label', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _RsvpSheet extends ConsumerStatefulWidget {
  const _RsvpSheet({required this.event});
  final ParentEvent event;

  @override
  ConsumerState<_RsvpSheet> createState() => _RsvpSheetState();
}

class _RsvpSheetState extends ConsumerState<_RsvpSheet> {
  late ParentEvent _e = widget.event;
  final _reasons = <String, TextEditingController>{};
  String? _busy; // 처리 중인 studentId
  String? _error;

  @override
  void dispose() {
    for (final c in _reasons.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _reason(ChildRsvp c) => _reasons.putIfAbsent(c.studentId, () => TextEditingController(text: c.reason ?? ''));

  Future<void> _answer(ChildRsvp c, String answer) async {
    setState(() {
      _busy = c.studentId;
      _error = null;
    });
    try {
      final updated = await ref.read(parentRepositoryProvider).respond(_e.id, c.studentId, answer, answer == 'ABSENT' ? _reason(c).text : null);
      setState(() => _e = updated);
      ref.invalidate(eventsProvider);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final df = DateFormat('M월 d일 (E) HH:mm', 'ko_KR');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                '${df.format(e.startsAt)}${e.endsAt != null ? ' ~ ${DateFormat('HH:mm').format(e.endsAt!)}' : ''}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (e.location != null) Text(e.location!, style: const TextStyle(color: AppColors.textSecondary)),
              Text(e.institutionName, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              if (e.canceled) ...[
                const SizedBox(height: 12),
                const Text('취소된 행사입니다', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              ],
              if (e.body != null && e.body!.isNotEmpty) ...[
                const Divider(height: 28),
                Text(e.body!, style: const TextStyle(height: 1.6)),
              ],
              if (e.rsvpEnabled && !e.canceled) ...[
                const Divider(height: 28),
                Text(
                  e.open
                      ? '참석 여부를 알려 주세요${e.rsvpDeadline != null ? ' (${DateFormat('M/d HH:mm').format(e.rsvpDeadline!)} 마감)' : ''}'
                      : '응답이 마감되었습니다',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final c in e.children) ...[
                  Row(children: [
                    Expanded(child: Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    if (_busy == c.studentId) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ]),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(value: 'ATTEND', label: Text('참석'), icon: Icon(Icons.check)),
                      ButtonSegment(value: 'ABSENT', label: Text('불참'), icon: Icon(Icons.close)),
                    ],
                    selected: {if (c.answer != null) c.answer!},
                    onSelectionChanged: !e.open || _busy != null ? null : (s) => s.isEmpty ? null : _answer(c, s.first),
                  ),
                  if (c.answer == 'ABSENT' && e.open)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: _reason(c),
                        maxLength: 200,
                        decoration: InputDecoration(
                          labelText: '불참 사유 (선택)',
                          isDense: true,
                          suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _busy != null ? null : () => _answer(c, 'ABSENT')),
                        ),
                      ),
                    )
                  else if (c.reason != null && c.reason!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('사유: ${c.reason}', style: const TextStyle(color: AppColors.textSecondary))),
                  const SizedBox(height: 16),
                ],
                if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
