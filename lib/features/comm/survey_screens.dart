import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'comm_models.dart';
import 'comm_repository.dart';
import '../../core/i18n/i18n.dart';

/// NTC-010 학부모: 받은 설문 (진행 중 먼저)
class SurveyListScreen extends ConsumerWidget {
  const SurveyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(surveysProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('설문'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(surveysProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorMessage(e))),
          data: (items) => items.isEmpty
              ? ListView(children: [SizedBox(height: 120), Center(child: Text(tr('받은 설문이 없습니다'), style: TextStyle(color: AppColors.textSecondary)))])
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = items[i];
                    return ListTile(
                      title: Text(s.title, style: TextStyle(fontWeight: s.needsAnswer ? FontWeight.w800 : FontWeight.w500)),
                      subtitle: Text([
                        s.institutionName,
                        if (s.closesAt != null) tr('마감 {0}', [DateFormat('M/d HH:mm').format(s.closesAt!)]),
                      ].join(' · ')),
                      trailing: s.needsAnswer
                          ? Chip(label: Text(tr('응답하기')))
                          : Text(s.open ? tr('응답 완료') : tr('마감'), style: const TextStyle(color: AppColors.textSecondary)),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SurveyAnswerScreen(survey: s)));
                        ref.invalidate(surveysProvider);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// 설문 응답 — 자녀(원생)별로 한 번씩. 자녀가 여럿이면 아직 안 한 아이를 골라 응답한다.
class SurveyAnswerScreen extends ConsumerStatefulWidget {
  const SurveyAnswerScreen({super.key, required this.survey});
  final ParentSurvey survey;

  @override
  ConsumerState<SurveyAnswerScreen> createState() => _SurveyAnswerScreenState();
}

class _SurveyAnswerScreenState extends ConsumerState<SurveyAnswerScreen> {
  final _answers = <String, List<String>>{};
  final _texts = <String, TextEditingController>{};
  late String? _studentId;
  bool _busy = false;
  late Set<String> _doneNow;

  ParentSurvey get s => widget.survey;

  @override
  void initState() {
    super.initState();
    _doneNow = {for (final c in s.children.where((c) => c.answered)) c.studentId};
    _studentId = s.children.where((c) => !c.answered).map((c) => c.studentId).firstOrNull;
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _values(SurveyQuestion q) => q.type == 'TEXT' ? [if ((_texts[q.id]?.text.trim() ?? '').isNotEmpty) _texts[q.id]!.text.trim()] : (_answers[q.id] ?? const []);

  bool get _valid => _studentId != null && s.questions.every((q) => !q.required || _values(q).isNotEmpty);

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(commRepositoryProvider).submitSurvey(s.id, _studentId!, {for (final q in s.questions) q.id: _values(q)});
      _doneNow.add(_studentId!);
      final next = s.children.where((c) => !_doneNow.contains(c.studentId)).map((c) => c.studentId).firstOrNull;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('응답을 보냈습니다'))));
      if (next == null) {
        Navigator.pop(context);
      } else {
        setState(() {
          _studentId = next;
          _answers.clear();
          for (final c in _texts.values) {
            c.clear();
          }
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = s.open && _studentId != null;
    return Scaffold(
      appBar: AppBar(title: Text(s.title, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (s.description != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(s.description!, style: const TextStyle(height: 1.5))),
        if (!s.open) Text(tr('마감된 설문입니다.'), style: TextStyle(color: AppColors.textSecondary)),
        if (s.open && _studentId == null) Text(tr('모든 자녀의 응답을 마쳤습니다.'), style: TextStyle(color: AppColors.textSecondary)),
        if (editable && s.children.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              value: _studentId,
              decoration: InputDecoration(labelText: tr('응답할 아이')),
              items: [for (final c in s.children.where((c) => !_doneNow.contains(c.studentId))) DropdownMenuItem(value: c.studentId, child: Text(c.name))],
              onChanged: (v) => setState(() => _studentId = v),
            ),
          ),
        if (editable)
          for (final (i, q) in s.questions.indexed) ...[
            Text('Q${i + 1}. ${q.text}${q.required ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            _input(q),
            const SizedBox(height: 20),
          ],
        if (editable) FilledButton(onPressed: _valid && !_busy ? _submit : null, child: Text(tr('제출'))),
      ]),
    );
  }

  Widget _input(SurveyQuestion q) {
    switch (q.type) {
      case 'TEXT':
        return TextField(controller: _texts.putIfAbsent(q.id, TextEditingController.new), maxLines: 3, maxLength: 1000, onChanged: (_) => setState(() {}), decoration: const InputDecoration(border: OutlineInputBorder()));
      case 'RATING':
        final cur = int.tryParse(_answers[q.id]?.firstOrNull ?? '') ?? 0;
        return Row(children: [
          for (var n = 1; n <= 5; n++)
            IconButton(
              onPressed: () => setState(() => _answers[q.id] = ['$n']),
              icon: Icon(n <= cur ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
            ),
        ]);
      case 'MULTI':
        return Column(children: [
          for (final o in q.options)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(o),
              value: _answers[q.id]?.contains(o) ?? false,
              onChanged: (v) => setState(() {
                final l = [...?_answers[q.id]];
                v == true ? l.add(o) : l.remove(o);
                _answers[q.id] = l;
              }),
            ),
        ]);
      default: // SINGLE
        return RadioGroup<String>(
          groupValue: _answers[q.id]?.firstOrNull,
          onChanged: (v) => setState(() => _answers[q.id] = [if (v != null) v]),
          child: Column(children: [for (final o in q.options) RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, title: Text(o), value: o)]),
        );
    }
  }
}
