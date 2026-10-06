import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import 'models.dart';

/// 학부모 API (/me/*). 기관 헤더를 붙이지 않는다 — 여러 학원에 다니는 자녀를 한 번에 본다.
class ParentRepository {
  ParentRepository(this._api);

  final ApiClient _api;
  Dio get _dio => _api.dio;

  static final _me = Options(extra: {'noInstitution': true});
  static final _date = DateFormat('yyyy-MM-dd');

  Future<List<Child>> children() => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/children', options: _me);
        return r.data!.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// PAR-001 커서 페이징: before = 마지막 항목의 occurredAt
  Future<List<TimelineItem>> timeline({String? childId, DateTime? before, int limit = 20}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/timeline', options: _me, queryParameters: {
          if (childId != null) 'childId': childId,
          if (before != null) 'before': before.toUtc().toIso8601String(),
          'limit': limit,
        });
        return r.data!.map((e) => TimelineItem.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// PAR-004 알림장함 (첨부 URL 은 상세에서만)
  Future<List<ParentNotice>> notices({String? childId, DateTime? before, int limit = 20}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/notices', options: _me, queryParameters: {
          if (childId != null) 'childId': childId,
          if (before != null) 'before': before.toUtc().toIso8601String(),
          'limit': limit,
        });
        return r.data!.map((e) => ParentNotice.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<ParentNotice> notice(String id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('me/notices/$id', options: _me);
        return ParentNotice.fromJson(r.data!);
      });

  /// 상세 화면 최초 진입 = 열람 (푸시 수신만으로는 열람 아님). 재호출해도 최초 시각 유지
  Future<void> markNoticeRead(String id) => _call(() => _dio.post<void>('me/notices/$id/read', options: _me));

  /// PAR-005
  Future<List<ParentEvent>> events({String? childId, bool includePast = false}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/events', options: _me, queryParameters: {
          if (childId != null) 'childId': childId,
          'includePast': includePast,
        });
        return r.data!.map((e) => ParentEvent.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// 자녀별 참석 응답 (마감 후 403)
  Future<ParentEvent> respond(String eventId, String studentId, String answer, String? reason) => _call(() async {
        final r = await _dio.put<Map<String, dynamic>>('me/events/$eventId/response', options: _me, data: {
          'studentId': studentId,
          'answer': answer,
          'reason': (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
        });
        return ParentEvent.fromJson(r.data!);
      });

  /// PAR-003 주간 스케줄 (week = 그 주 아무 날)
  Future<WeekSchedule> schedule({String? childId, DateTime? week}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('me/schedule', options: _me, queryParameters: {
          if (childId != null) 'childId': childId,
          if (week != null) 'week': _date.format(week),
        });
        return WeekSchedule.fromJson(r.data!);
      });

  /// SET-005 아직 동의하지 않은 학부모 약관 (개정 시 재동의)
  Future<List<Terms>> pendingTerms() => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/terms/pending', options: _me, queryParameters: {'audience': 'PARENT'});
        return r.data!.map((e) => Terms.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> agreeTerms(List<String> ids) => _call(() => _dio.post<void>('me/terms/agreements', options: _me, data: {'termsIds': ids}));

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final parentRepositoryProvider = Provider<ParentRepository>((ref) => ParentRepository(ref.watch(apiClientProvider)));

/// 가입 화면용 — 로그인 전 공개 약관
Future<List<Terms>> fetchPublicParentTerms(ApiClient api) async {
  try {
    final list = await api.publicGet<List<dynamic>>('terms', query: {'audience': 'PARENT'});
    return list.map((e) => Terms.fromJson(e as Map<String, dynamic>)).toList();
  } catch (e) {
    throw ApiException.from(e);
  }
}
