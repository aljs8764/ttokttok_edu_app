import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/date_time_field.dart';
import 'content_models.dart';
import 'content_providers.dart';
import 'content_repository.dart';
import 'target_picker.dart';

const _reminderOptions = <int, String>{
  6: '마감 6시간 전',
  12: '마감 12시간 전',
  24: '마감 하루 전',
  48: '마감 이틀 전',
  72: '마감 사흘 전',
};

/// EVT-001 행사 만들기 + 참석 여부(RSVP) 받기. [id] 가 있으면 수정 (대상·RSVP 사용 여부는 못 바꾼다).
/// 마감 전 정한 시점에 미응답 보호자께 자동 독촉 푸시가 한 번 간다 (서버 5분 주기 스케줄러).
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _location = TextEditingController();
  DateTime? _startsAt = _defaultAt(7, 10);
  DateTime? _endsAt;
  List<Target> _targets = [];
  bool _rsvp = true;
  DateTime? _deadline = _defaultAt(5, 18);
  int _reminder = 24;

  bool _loading = false;
  bool _locked = false; // 취소된 행사는 수정 불가
  bool _busy = false;
  String? _error;

  bool get _editing => widget.id != null;

  static DateTime _defaultAt(int daysAhead, int hour) {
    final d = DateTime.now().add(Duration(days: daysAhead));
    return DateTime(d.year, d.month, d.day, hour);
  }

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = (await ref.read(contentRepositoryProvider).eventSummary(widget.id!)).event;
      if (!mounted) return;
      setState(() {
        _title.text = e.title;
        _body.text = e.body ?? '';
        _location.text = e.location ?? '';
        _startsAt = e.startsAt;
        _endsAt = e.endsAt;
        _targets = e.targets;
        _rsvp = e.rsvpEnabled;
        _deadline = e.rsvpDeadline;
        _reminder = _reminderOptions.containsKey(e.reminderHoursBefore) ? e.reminderHoursBefore! : 24;
        _locked = e.canceled;
      });
    } catch (err) {
      if (mounted) setState(() => _error = errorMessage(err));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 웹과 같은 검사 (생성일 때만 "현재 이후")
  String? get _timeError {
    final now = DateTime.now();
    final s = _startsAt;
    if (s == null) return '시작 시각을 고르세요';
    if (!_editing && !s.isAfter(now)) return '행사 시작은 현재 이후여야 합니다';
    if (_endsAt != null && !_endsAt!.isAfter(s)) return '종료는 시작 이후여야 합니다';
    if (_rsvp) {
      final d = _deadline;
      if (d == null) return '응답 마감 시각을 고르세요';
      if (d.isAfter(s)) return '응답 마감은 행사 시작 전이어야 합니다';
      if (!_editing && !d.isAfter(now)) return '응답 마감은 현재 이후여야 합니다';
    }
    return null;
  }

  bool get _valid => _title.text.trim().isNotEmpty && (_editing || _targets.isNotEmpty) && _timeError == null && !_locked;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft = EventDraft(
        title: _title.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        startsAt: _startsAt!,
        endsAt: _endsAt,
        targets: _targets,
        rsvpEnabled: _rsvp,
        rsvpDeadline: _rsvp ? _deadline : null,
        reminderHoursBefore: _rsvp ? _reminder : null,
      );
      final repo = ref.read(contentRepositoryProvider);
      final e = _editing ? await repo.updateEvent(widget.id!, draft) : await repo.createEvent(draft);
      invalidateEvents(ref, id: e.id);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_editing ? '저장했습니다' : '행사를 만들고 학부모께 알렸습니다')));
      if (_editing) {
        context.pop();
      } else {
        context.pushReplacement('/events/${e.id}');
      }
    } catch (err) {
      if (mounted) setState(() => _error = errorMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_locked && !_busy;
    final timeError = _timeError;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '행사 수정' : '행사 만들기')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_locked) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('취소된 행사는 수정할 수 없습니다.', style: TextStyle(color: AppColors.info))),
                  TextField(
                    controller: _title,
                    enabled: enabled,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: '행사명', hintText: '예: 가을 소풍'),
                  ),
                  const SizedBox(height: 12),
                  DateTimeField(
                    label: '시작',
                    value: _startsAt,
                    enabled: enabled,
                    first: _editing ? null : DateTime.now(),
                    last: DateTime.now().add(const Duration(days: 730)),
                    onChanged: (d) => setState(() => _startsAt = d),
                  ),
                  const SizedBox(height: 12),
                  DateTimeField(
                    label: '종료 (선택)',
                    value: _endsAt,
                    enabled: enabled,
                    first: _startsAt,
                    last: DateTime.now().add(const Duration(days: 730)),
                    onChanged: (d) => setState(() => _endsAt = d),
                    onClear: () => setState(() => _endsAt = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _location, enabled: enabled, maxLength: 200, decoration: const InputDecoration(labelText: '장소')),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _body,
                    enabled: enabled,
                    maxLength: 5000,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(labelText: '안내 내용', hintText: '준비물, 회비, 복장 등', alignLabelWithHint: true),
                  ),
                  const Divider(height: 32),
                  if (_editing) ...[
                    Text('받는 사람: ${_targets.map((t) => t.name ?? '').join(', ')}', style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    const Text('받는 사람은 행사를 만든 뒤에는 바꿀 수 없습니다.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ] else
                    TargetPicker(value: _targets, enabled: enabled, onChanged: (t) => setState(() => _targets = t)),
                  const Divider(height: 32),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('참석 여부 받기 (RSVP)'),
                    // 수정에서는 RSVP 사용 여부를 바꾸지 못한다 (백엔드 UpdateRequest 에 없음)
                    value: _rsvp,
                    onChanged: enabled && !_editing ? (v) => setState(() => _rsvp = v) : null,
                  ),
                  if (_rsvp) ...[
                    const SizedBox(height: 8),
                    DateTimeField(
                      label: '응답 마감',
                      value: _deadline,
                      enabled: enabled,
                      first: _editing ? null : DateTime.now(),
                      last: _startsAt,
                      onChanged: (d) => setState(() => _deadline = d),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _reminder,
                      decoration: const InputDecoration(labelText: '자동 독촉', helperText: '미응답 보호자께 한 번 푸시'),
                      items: [for (final e in _reminderOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: enabled ? (v) => setState(() => _reminder = v ?? 24) : null,
                    ),
                  ],
                  if (timeError != null && _startsAt != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(timeError, style: const TextStyle(color: AppColors.error))),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _valid && !_busy ? _submit : null,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? '저장' : '만들고 알리기'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
