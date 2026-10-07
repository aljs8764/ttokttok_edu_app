import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/parent/models.dart' show FileAttachment;

/// 알림장 첨부 한 개. 이미지는 바로 보여 주고, PDF 등은 눌러서 외부 앱(브라우저·뷰어)으로 열고 길게 누르면 링크를 복사한다.
/// 학부모 알림장 상세와 교사 알림장 상세가 같이 쓴다.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile(this.a, {super.key});

  final FileAttachment a;

  @override
  Widget build(BuildContext context) {
    final url = a.downloadUrl;
    if (a.isImage && url != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fileRow(context, url),
            loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          ),
        ),
      );
    }
    return _fileRow(context, url);
  }

  Widget _fileRow(BuildContext context, String? url) => Card(
        child: ListTile(
          leading: const Icon(Icons.attach_file),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(fileSizeLabel(a.size)),
          trailing: url == null ? null : const Icon(Icons.open_in_new, size: 18),
          onTap: url == null ? null : () => _open(context, url),
          onLongPress: url == null ? null : () => _copy(context, url),
        ),
      );
}

Future<void> _open(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(const SnackBar(content: Text('열 수 있는 앱이 없어 파일 링크를 복사했습니다 (5분 동안 열 수 있어요)')));
  }
}

void _copy(BuildContext context, String url) {
  Clipboard.setData(ClipboardData(text: url));
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('파일 링크를 복사했습니다 (5분 동안 열 수 있어요)')));
}

String fileSizeLabel(int n) => n < 1024 * 1024 ? '${(n / 1024).ceil()}KB' : '${(n / 1024 / 1024).toStringAsFixed(1)}MB';
