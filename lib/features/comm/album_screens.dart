import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'comm_models.dart';
import 'comm_repository.dart';
import '../../core/i18n/i18n.dart';

/// NTC-011 학부모: 앨범 목록
class AlbumListScreen extends ConsumerWidget {
  const AlbumListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(albumsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('앨범'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(albumsProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorMessage(e))),
          data: (items) => items.isEmpty
              ? ListView(children: [SizedBox(height: 120), Center(child: Text(tr('공유된 앨범이 없습니다'), style: TextStyle(color: AppColors.textSecondary)))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final a = items[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push('/albums/${a.id}'),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            height: 110,
                            child: Row(children: [for (final it in a.items.take(4)) Expanded(child: _Thumb(it))]),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(tr('{0} · {1}개 · {2}', [a.institutionName, a.itemCount, DateFormat(tr('M월 d일'), dateLocale()).format(a.createdAt)]), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.item);
  final AlbumItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.file.downloadUrl;
    if (item.isVideo || url == null) {
      return Container(color: Colors.black12, child: Icon(item.isVideo ? Icons.play_circle_outline : Icons.image_outlined));
    }
    return Image.network(url, fit: BoxFit.cover, height: double.infinity, errorBuilder: (_, __, ___) => Container(color: Colors.black12));
  }
}

/// 앨범 상세 — 사진은 격자(누르면 크게), 영상은 외부 플레이어로 연다. 다운로드 링크는 5분만 유효해서 화면을 열 때마다 새로 받는다.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(album.valueOrNull?.title ?? tr('앨범'), overflow: TextOverflow.ellipsis)),
      body: album.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (a) => ListView(padding: const EdgeInsets.all(12), children: [
          if (a.description != null) Padding(padding: const EdgeInsets.all(8), child: Text(a.description!, style: const TextStyle(height: 1.5))),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), child: Text('${a.authorName} · ${DateFormat('M월 d일 HH:mm').format(a.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final it in a.items)
                GestureDetector(
                  onTap: () => _open(context, it),
                  child: Stack(fit: StackFit.expand, children: [
                    _Thumb(it),
                    if (it.isVideo) const Align(alignment: Alignment.bottomRight, child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.videocam, color: Colors.white, size: 18))),
                  ]),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _open(BuildContext context, AlbumItem it) async {
    final url = it.file.downloadUrl;
    if (url == null) return;
    if (it.isVideo) {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('영상을 열 수 있는 앱이 없습니다'))));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          Center(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
          Positioned(top: 32, right: 8, child: IconButton(color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
        ]),
      ),
    );
  }
}
