import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/attachment_tile.dart' show fileSizeLabel;
import '../parent/models.dart' show FileAttachment;
import 'content_repository.dart';

/// 사진 첨부 (카메라 / 앨범, 최대 [max]개, 20MB). 고르는 즉시 업로드하고 파일 id 만 폼에 남긴다.
/// PDF 첨부는 관리자 웹에서 (앱은 사진만).
class AttachmentField extends ConsumerStatefulWidget {
  const AttachmentField({super.key, required this.value, required this.onChanged, this.max = 10, this.enabled = true});

  final List<FileAttachment> value;
  final ValueChanged<List<FileAttachment>> onChanged;
  final int max;
  final bool enabled;

  @override
  ConsumerState<AttachmentField> createState() => _AttachmentFieldState();
}

class _AttachmentFieldState extends ConsumerState<AttachmentField> {
  final _picker = ImagePicker();
  int _uploading = 0;
  String? _error;

  int get _remaining => widget.max - widget.value.length;

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    final List<XFile> picked;
    try {
      if (source == ImageSource.camera) {
        final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048);
        picked = f == null ? const [] : [f];
      } else {
        picked = (await _picker.pickMultiImage(imageQuality: 85, maxWidth: 2048)).take(_remaining).toList();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '사진을 불러오지 못했습니다. 카메라·사진 접근 권한을 확인하세요');
      return;
    }
    if (picked.isEmpty) return;

    setState(() => _uploading = picked.length);
    final done = <FileAttachment>[];
    for (final f in picked) {
      try {
        done.add(await ref.read(contentRepositoryProvider).uploadNoticeImage(f));
      } catch (e) {
        if (mounted) setState(() => _error = '${f.name}: ${errorMessage(e)}');
      }
      if (mounted) setState(() => _uploading--);
    }
    if (done.isNotEmpty && mounted) widget.onChanged([...widget.value, ...done]);
  }

  void _showSources() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('사진 찍기'),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('앨범에서 고르기'),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.enabled && _uploading == 0 && _remaining > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: canAdd ? _showSources : null,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('사진 첨부'),
          ),
          const SizedBox(width: 12),
          Text('${widget.value.length}/${widget.max}', style: const TextStyle(color: AppColors.textSecondary)),
        ]),
        if (widget.value.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final f in widget.value)
                InputChip(
                  avatar: const Icon(Icons.image_outlined, size: 18),
                  label: Text('${f.name} · ${fileSizeLabel(f.size)}', overflow: TextOverflow.ellipsis),
                  onDeleted: widget.enabled ? () => widget.onChanged(widget.value.where((x) => x.id != f.id).toList()) : null,
                ),
            ]),
          ),
        if (_uploading > 0) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: AppColors.warning))),
      ],
    );
  }
}
