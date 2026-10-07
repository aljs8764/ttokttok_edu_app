import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/widgets/date_time_field.dart';
import '../parent/models.dart' show FileAttachment;
import 'attachment_field.dart';
import 'content_models.dart';
import 'content_providers.dart';
import 'content_repository.dart';
import 'target_picker.dart';

/// NTC-001 알림장·공지 작성 (즉시 / 예약 발송, 사진 최대 10장). [id] 가 있으면 예약 건 수정.
/// 공지와 전체 대상은 원장·실장만. 예약은 30일 이내.
class NoticeFormScreen extends ConsumerStatefulWidget {
  const NoticeFormScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<NoticeFormScreen> createState() => _NoticeFormScreenState();
}

class _NoticeFormScreenState extends ConsumerState<NoticeFormScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  NoticeKind _kind = NoticeKind.note;
  bool _pinned = false;
  List<Target> _targets = [];
  List<FileAttachment> _attachments = [];
  bool _scheduled = false;
  DateTime? _sendAt;

  bool _loading = false;
  bool _locked = false; // 이미 발송·취소된 건은 수정 불가
  bool _busy = false;
  String? _error;

  bool get _editing => widget.id != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final n = await ref.read(contentRepositoryProvider).notice(widget.id!);
      if (!mounted) return;
      setState(() {
        _kind = n.kind;
        _title.text = n.title;
        _body.text = n.body;
        _pinned = n.pinned;
        _targets = n.targets;
        _attachments = n.attachments;
        _scheduled = true;
        _sendAt = n.scheduledAt;
        _locked = n.status != NoticeStatus.scheduled;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _scheduleError {
    if (!_scheduled) return null;
    final at = _sendAt;
    if (at == null) return '예약 시각을 고르세요';
    final now = DateTime.now();
    if (!at.isAfter(now)) return '현재 이후로 고르세요';
    if (at.isAfter(now.add(const Duration(days: 30)))) return '30일 이내로만 예약할 수 있습니다';
    return null;
  }

  bool get _valid => _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty && _targets.isNotEmpty && _scheduleError == null && !_locked;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft = NoticeDraft(
        kind: _kind,
        title: _title.text.trim(),
        body: _body.text.trim(),
        pinned: _kind == NoticeKind.announcement && _pinned,
        targets: _targets,
        attachmentIds: _attachments.map((a) => a.id).toList(),
        sendAt: _scheduled ? _sendAt : null,
      );
      final repo = ref.read(contentRepositoryProvider);
      final n = _editing ? await repo.updateNotice(widget.id!, draft) : await repo.createNotice(draft);
      invalidateNotices(ref, id: n.id);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_editing ? '저장했습니다' : (_scheduled ? '예약했습니다' : '학부모 앱으로 보냈습니다'))));
      if (_editing) {
        context.pop();
      } else {
        context.pushReplacement('/notices/${n.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(authControllerProvider).membership?.role.isManager ?? false;
    final enabled = !_locked && !_busy;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '예약 알림장 수정' : '알림장 쓰기')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_locked)
                    const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('이미 발송되었거나 취소된 알림장은 수정할 수 없습니다.', style: TextStyle(color: AppColors.info))),
                  if (manager)
                    SegmentedButton<NoticeKind>(
                      segments: const [
                        ButtonSegment(value: NoticeKind.note, label: Text('알림장')),
                        ButtonSegment(value: NoticeKind.announcement, label: Text('공지')),
                      ],
                      selected: {_kind},
                      onSelectionChanged: enabled ? (s) => setState(() => _kind = s.first) : null,
                    ),
                  if (manager) const SizedBox(height: 16),
                  TargetPicker(value: _targets, enabled: enabled, onChanged: (t) => setState(() => _targets = t)),
                  const Divider(height: 32),
                  TextField(
                    controller: _title,
                    enabled: enabled,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: '제목'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _body,
                    enabled: enabled,
                    maxLength: 5000,
                    minLines: 8,
                    maxLines: 14,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: '내용', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 8),
                  AttachmentField(value: _attachments, enabled: enabled, onChanged: (v) => setState(() => _attachments = v)),
                  if (_kind == NoticeKind.announcement)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('학부모 앱 상단에 고정'),
                      value: _pinned,
                      onChanged: enabled ? (v) => setState(() => _pinned = v ?? false) : null,
                    ),
                  const Divider(height: 32),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('바로 보내기')),
                      ButtonSegment(value: true, label: Text('예약 발송')),
                    ],
                    selected: {_scheduled},
                    // 수정은 예약 건만 가능하므로 방식은 바꾸지 않는다
                    onSelectionChanged: enabled && !_editing ? (s) => setState(() => _scheduled = s.first) : null,
                  ),
                  if (_scheduled) ...[
                    const SizedBox(height: 12),
                    DateTimeField(
                      label: '보낼 시각',
                      value: _sendAt,
                      enabled: enabled,
                      first: DateTime.now(),
                      last: DateTime.now().add(const Duration(days: 30)),
                      errorText: _sendAt == null ? null : _scheduleError,
                      onChanged: (d) => setState(() => _sendAt = d),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    '학부모 앱으로 푸시가 갑니다. 열람 여부는 상세 화면의 수신 확인에서 보고, 안 읽은 분께만 다시 보낼 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _valid && !_busy ? _submit : null,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? '저장' : (_scheduled ? '예약하기' : '보내기')),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
