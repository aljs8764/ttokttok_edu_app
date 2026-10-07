import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import 'content_models.dart';
import 'content_repository.dart';
import 'models.dart' show Classroom;
import 'teacher_providers.dart';

/// 알림장·행사 받는 사람 (전체 / 반 / 원생 개별). 대상이 겹쳐도 백엔드가 원생 단위로 중복 제거한다.
/// 전체는 원장·실장만, 교사는 담당 반과 그 반 원생만 (백엔드도 검사).
class TargetPicker extends ConsumerStatefulWidget {
  const TargetPicker({super.key, required this.value, required this.onChanged, this.enabled = true});

  final List<Target> value;
  final ValueChanged<List<Target>> onChanged;
  final bool enabled;

  @override
  ConsumerState<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends ConsumerState<TargetPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<StudentRef> _results = const [];
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _all => widget.value.any((t) => t.isAll);

  void _toggleClass(Classroom c) {
    final t = Target(scope: 'CLASS', id: c.id, name: c.name);
    final v = [...widget.value];
    if (!v.remove(t)) v.add(t);
    widget.onChanged(v);
  }

  void _addStudent(StudentRef s) {
    final t = Target(scope: 'STUDENT', id: s.id, name: s.name);
    if (!widget.value.contains(t)) widget.onChanged([...widget.value, t]);
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    final keyword = q.trim();
    if (keyword.isEmpty) {
      setState(() {
        _results = const [];
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _searching = true;
        _searchError = null;
      });
      try {
        final r = await ref.read(contentRepositoryProvider).searchStudents(keyword);
        if (!mounted || _search.text.trim() != keyword) return;
        setState(() => _results = r);
      } catch (e) {
        if (mounted) setState(() => _searchError = errorMessage(e));
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(authControllerProvider).membership?.role.isManager ?? false;
    final classes = ref.watch(classesProvider);
    final selectedClassIds = widget.value.where((t) => t.scope == 'CLASS').map((t) => t.id).toSet();
    final selectedStudents = widget.value.where((t) => t.scope == 'STUDENT').toList();
    final pickedIds = selectedStudents.map((t) => t.id).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('받는 사람', style: TextStyle(fontWeight: FontWeight.w700)),
        if (manager)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('기관 전체 (재원생 모두)'),
            value: _all,
            onChanged: widget.enabled ? (v) => widget.onChanged(v ? const [Target.all] : const []) : null,
          ),
        if (!_all) ...[
          const SizedBox(height: 8),
          const Text('반 (여러 개 선택 가능)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          classes.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorMessage(e), style: const TextStyle(color: AppColors.error)),
            data: (list) => list.isEmpty
                ? const Text('선택할 수 있는 반이 없습니다', style: TextStyle(color: AppColors.textSecondary))
                : Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final c in list)
                      FilterChip(
                        label: Text('${c.name}${c.headcount != null ? ' ${c.headcount}명' : ''}'),
                        selected: selectedClassIds.contains(c.id),
                        onSelected: widget.enabled ? (_) => _toggleClass(c) : null,
                      ),
                  ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            enabled: widget.enabled,
            onChanged: _onQuery,
            decoration: InputDecoration(
              labelText: '원생 개별 추가',
              hintText: '이름 또는 보호자 번호 뒷 4자리',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
          if (_searchError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_searchError!, style: const TextStyle(color: AppColors.error))),
          if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final s in _results)
                  if (!pickedIds.contains(s.id)) ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(s.name), onPressed: widget.enabled ? () => _addStudent(s) : null),
              ]),
            )
          else if (_search.text.trim().isNotEmpty && !_searching && _searchError == null)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('찾는 원생이 없습니다', style: TextStyle(color: AppColors.textSecondary))),
          if (selectedStudents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final t in selectedStudents)
                  InputChip(
                    label: Text(t.name ?? ''),
                    onDeleted: widget.enabled ? () => widget.onChanged([...widget.value]..remove(t)) : null,
                  ),
              ]),
            ),
        ],
      ],
    );
  }
}
