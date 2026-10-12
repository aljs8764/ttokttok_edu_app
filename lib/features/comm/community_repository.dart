import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';

// P3-⑦ 익명 커뮤니티 (COM-001~009). 교사앱·학부모앱 공통, 기관 헤더 없이 사용자 단위.
// 응답에는 작성자 신원이 없다 — mine(본인 여부)과 익명 번호만.

DateTime _ts(Object? v) => DateTime.parse(v as String).toLocal();

class CommunityBoard {
  CommunityBoard.fromJson(Map<String, dynamic> j)
      : key = j['key'] as String,
        scope = j['scope'] as String,
        audience = j['audience'] as String,
        institutionName = j['institutionName'] as String?;
  final String key;
  final String scope;
  final String audience;
  final String? institutionName;

  bool get lounge => scope == 'LOUNGE';

  String get label {
    if (lounge) {
      return tr(audience == 'OWNER' ? '원장 라운지' : audience == 'STAFF' ? '교사 라운지' : '학부모 라운지');
    }
    return tr(audience == 'STAFF' ? '{0} 교직원' : '{0} 학부모', [institutionName ?? '']);
  }
}

class CommunityPost {
  CommunityPost.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        boardKey = j['boardKey'] as String,
        category = j['category'] as String,
        title = j['title'] as String,
        preview = (j['preview'] as String?) ?? '',
        authorRole = j['authorRole'] as String?,
        authorRegion = j['authorRegion'] as String?,
        likeCount = (j['likeCount'] as num).toInt(),
        commentCount = (j['commentCount'] as num).toInt(),
        mine = j['mine'] as bool? ?? false,
        hidden = j['hidden'] as String?,
        createdAt = _ts(j['createdAt']);
  final String id;
  final String boardKey;
  final String category;
  final String title;
  final String preview;
  final String? authorRole;
  final String? authorRegion;
  final int likeCount;
  final int commentCount;
  final bool mine;
  final String? hidden;
  final DateTime createdAt;

  /// 라운지 '원장 · 서울', 기관 게시판 '익명'
  String get author {
    if (authorRole == null) return tr('익명');
    final role = tr(communityRoleLabel(authorRole!));
    return authorRegion == null ? role : '$role · $authorRegion';
  }
}

class CommunityComment {
  CommunityComment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        parentId = j['parentId'] as String?,
        anonNo = (j['anonNo'] as num).toInt(),
        body = j['body'] as String?,
        likeCount = (j['likeCount'] as num).toInt(),
        liked = j['liked'] as bool? ?? false,
        mine = j['mine'] as bool? ?? false,
        deleted = j['deleted'] as bool? ?? false,
        hidden = j['hidden'] as bool? ?? false,
        createdAt = _ts(j['createdAt']);
  final String id;
  final String? parentId;
  final int anonNo;
  final String? body;
  final int likeCount;
  final bool liked;
  final bool mine;
  final bool deleted;
  final bool hidden;
  final DateTime createdAt;
}

class CommunityPostDetail {
  CommunityPostDetail.fromJson(Map<String, dynamic> j)
      : post = CommunityPost.fromJson(j['post'] as Map<String, dynamic>),
        body = j['body'] as String,
        liked = j['liked'] as bool? ?? false,
        comments = (j['comments'] as List<dynamic>).map((e) => CommunityComment.fromJson(e as Map<String, dynamic>)).toList();
  final CommunityPost post;
  final String body;
  final bool liked;
  final List<CommunityComment> comments;
}

class CommunityPage {
  CommunityPage.fromJson(Map<String, dynamic> j)
      : items = (j['items'] as List<dynamic>).map((e) => CommunityPost.fromJson(e as Map<String, dynamic>)).toList(),
        page = (j['page'] as num).toInt(),
        hasMore = j['hasMore'] as bool? ?? false;
  final List<CommunityPost> items;
  final int page;
  final bool hasMore;
}

class CommunityMe {
  CommunityMe.fromJson(Map<String, dynamic> j)
      : rulesAgreed = j['rulesAgreed'] as bool? ?? false,
        sanctionedUntil = j['sanctionedUntil'] == null ? null : _ts(j['sanctionedUntil']),
        sanctionPermanent = j['sanctionPermanent'] as bool? ?? false,
        sanctionReason = j['sanctionReason'] as String?,
        newComments = (j['newComments'] as num?)?.toInt() ?? 0;
  final bool rulesAgreed;
  final DateTime? sanctionedUntil;
  final bool sanctionPermanent;
  final String? sanctionReason;
  final int newComments;

  bool get sanctioned => sanctionPermanent || sanctionedUntil != null;
}

class MyCommunityComment {
  MyCommunityComment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        postId = j['postId'] as String,
        postTitle = j['postTitle'] as String,
        body = j['body'] as String?,
        deleted = j['deleted'] as bool? ?? false,
        createdAt = _ts(j['createdAt']);
  final String id;
  final String postId;
  final String postTitle;
  final String? body;
  final bool deleted;
  final DateTime createdAt;
}

const communityCategories = <String, String>{'FREE': '자유', 'QUESTION': '질문', 'INFO': '정보', 'WORRY': '고민'};
const communityReasons = <String, String>{'ABUSE': '욕설·비방', 'PRIVACY': '개인정보 노출', 'SPAM': '광고·홍보', 'OBSCENE': '음란·유해', 'OTHER': '기타'};
String communityRoleLabel(String role) => const {'OWNER': '원장', 'ADMIN': '실장', 'TEACHER': '교사', 'PARENT': '학부모'}[role] ?? role;
String anonLabel(int n) => n == 0 ? tr('글쓴이') : tr('익명{0}', [n]);

/// 방금 · n분 전 · n시간 전 · M/d
String communityAgo(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return tr('방금');
  if (m < 60) return tr('{0}분 전', [m]);
  if (m < 60 * 24) return tr('{0}시간 전', [m ~/ 60]);
  return t.year == DateTime.now().year ? '${t.month}/${t.day}' : '${t.year}.${t.month}.${t.day}';
}

const communityRules = <String>[
  "이름은 저장되지만 화면에는 보이지 않습니다. 라운지에서는 역할과 지역(시·도)만, 기관 게시판에서는 '익명'으로만 표시됩니다.",
  '특정 원생·학부모·교직원을 알아볼 수 있는 이름, 연락처, 사진 설명을 올리지 마세요. 전화번호·이메일은 자동으로 가려집니다.',
  '욕설·비방·차별 표현, 광고·홍보, 음란·유해 게시물은 금지됩니다.',
  '신고가 쌓이면 글이 자동으로 숨겨지고 운영사가 검토합니다. 규칙을 어기면 이용이 제한될 수 있습니다.',
  '명예훼손·모욕 등 법적 문제가 생기면 관련 법에 따라 처리될 수 있습니다.',
];

class CommunityRepository {
  CommunityRepository(this._api);
  final ApiClient _api;
  Dio get _dio => _api.dio;
  static final _me = Options(extra: {'noInstitution': true});

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Map<String, dynamic> _map(Response<Map<String, dynamic>> r) => r.data!;

  Future<List<CommunityBoard>> boards() => _call(() async {
        final r = await _dio.get<List<dynamic>>('community/boards', options: _me);
        return r.data!.map((e) => CommunityBoard.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<CommunityMe> me() => _call(() async => CommunityMe.fromJson(_map(await _dio.get<Map<String, dynamic>>('community/me', options: _me))));

  Future<CommunityMe> agreeRules() => _call(() async => CommunityMe.fromJson(_map(await _dio.post<Map<String, dynamic>>('community/rules', options: _me))));

  Future<CommunityPage> posts(String boardKey, {String sort = 'LATEST', String? category, String? q, int page = 0}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('community/boards/${Uri.encodeComponent(boardKey)}/posts', options: _me, queryParameters: {
          'sort': sort,
          if (category != null) 'category': category,
          if (q != null && q.isNotEmpty) 'q': q,
          'page': page,
        });
        return CommunityPage.fromJson(r.data!);
      });

  Future<CommunityPostDetail> post(String id) =>
      _call(() async => CommunityPostDetail.fromJson(_map(await _dio.get<Map<String, dynamic>>('community/posts/$id', options: _me))));

  Future<CommunityPostDetail> write(String boardKey, String category, String title, String body) => _call(() async => CommunityPostDetail.fromJson(_map(
      await _dio.post<Map<String, dynamic>>('community/boards/${Uri.encodeComponent(boardKey)}/posts', options: _me, data: {'category': category, 'title': title, 'body': body}))));

  Future<CommunityPostDetail> edit(String id, String category, String title, String body) => _call(() async => CommunityPostDetail.fromJson(
      _map(await _dio.put<Map<String, dynamic>>('community/posts/$id', options: _me, data: {'category': category, 'title': title, 'body': body}))));

  Future<void> deletePost(String id) => _call(() => _dio.delete<void>('community/posts/$id', options: _me));

  Future<CommunityPostDetail> comment(String postId, String body, {String? parentId}) => _call(() async => CommunityPostDetail.fromJson(
      _map(await _dio.post<Map<String, dynamic>>('community/posts/$postId/comments', options: _me, data: {'parentId': parentId, 'body': body}))));

  Future<void> deleteComment(String id) => _call(() => _dio.delete<void>('community/comments/$id', options: _me));

  /// type = posts | comments
  Future<void> like(String type, String id) => _call(() => _dio.post<void>('community/$type/$id/like', options: _me));

  Future<void> report(String type, String id, String reason, String? memo) =>
      _call(() => _dio.post<void>('community/$type/$id/report', options: _me, data: {'reason': reason, 'memo': memo}));

  Future<CommunityPage> myPosts({int page = 0}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('community/me/posts', options: _me, queryParameters: {'page': page});
        return CommunityPage.fromJson(r.data!);
      });

  Future<List<MyCommunityComment>> myComments() => _call(() async {
        final r = await _dio.get<List<dynamic>>('community/me/comments', options: _me, queryParameters: {'page': 0});
        return r.data!.map((e) => MyCommunityComment.fromJson(e as Map<String, dynamic>)).toList();
      });
}

final communityRepositoryProvider = Provider<CommunityRepository>((ref) => CommunityRepository(ref.watch(apiClientProvider)));
final communityBoardsProvider = FutureProvider.autoDispose<List<CommunityBoard>>((ref) => ref.watch(communityRepositoryProvider).boards());
final communityMeProvider = FutureProvider.autoDispose<CommunityMe>((ref) => ref.watch(communityRepositoryProvider).me());
final communityPostProvider = FutureProvider.autoDispose.family<CommunityPostDetail, String>((ref, id) => ref.watch(communityRepositoryProvider).post(id));
final myCommunityCommentsProvider = FutureProvider.autoDispose<List<MyCommunityComment>>((ref) => ref.watch(communityRepositoryProvider).myComments());
