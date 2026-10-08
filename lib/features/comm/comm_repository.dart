import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import 'comm_models.dart';

/// 소통 API. 학부모는 /me/* (기관 헤더 없음), 교직원은 기관 헤더가 자동으로 붙는 /conversations·/absence-requests.
class CommRepository {
  CommRepository(this._api);

  final ApiClient _api;
  Dio get _dio => _api.dio;

  static final _me = Options(extra: {'noInstitution': true});
  static final _date = DateFormat('yyyy-MM-dd');

  Options? _opt(bool staff) => staff ? null : _me;
  String _base(bool staff) => staff ? 'conversations' : 'me/conversations';

  // ── 대화 ──
  Future<List<Conversation>> conversations({required bool staff, bool unreadOnly = false}) => _call(() async {
        final r = await _dio.get<List<dynamic>>(_base(staff), options: _opt(staff), queryParameters: {
          if (staff && unreadOnly) 'unreadOnly': true,
          if (staff) 'size': 50 else 'limit': 50,
        });
        return r.data!.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// 학부모: 알림장에 회신하거나 선생님께 말 걸기. 같은 (원생, 알림장) 대화가 있으면 그대로 돌려준다.
  Future<Conversation> openAsParent(String studentId, {String? noticeId}) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('me/conversations/open', options: _me, data: {'studentId': studentId, if (noticeId != null) 'noticeId': noticeId});
        return Conversation.fromJson(r.data!);
      });

  /// 최신순으로 내려온다
  Future<List<ChatMessage>> messages(String id, {required bool staff}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('${_base(staff)}/$id/messages', options: _opt(staff), queryParameters: {'limit': 100});
        return r.data!.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<ChatMessage> send(String id, String body, {required bool staff}) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('${_base(staff)}/$id/messages', options: _opt(staff), data: {'body': body});
        return ChatMessage.fromJson(r.data!);
      });

  Future<void> markRead(String id, {required bool staff}) => _call(() => _dio.post<void>('${_base(staff)}/$id/read', options: _opt(staff)));

  // ── ATT-007 결석·지각·조퇴 신청 ──
  Future<List<AbsenceRequest>> myAbsenceRequests() => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/absence-requests', options: _me, queryParameters: {'limit': 50});
        return r.data!.map((e) => AbsenceRequest.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<AbsenceRequest> submitAbsence({required String studentId, required DateTime date, required String kind, required String reason, String? expectedTime}) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('me/absence-requests', options: _me, data: {
          'studentId': studentId,
          'date': _date.format(date),
          'kind': kind,
          'reason': reason,
          if (expectedTime != null) 'expectedTime': expectedTime,
        });
        return AbsenceRequest.fromJson(r.data!);
      });

  Future<void> cancelAbsence(String id) => _call(() => _dio.post<void>('me/absence-requests/$id/cancel', options: _me));

  /// 교직원: 오늘부터 2주
  Future<List<AbsenceRequest>> staffAbsenceRequests() => _call(() async {
        final today = DateTime.now();
        final r = await _dio.get<List<dynamic>>('absence-requests', queryParameters: {
          'from': _date.format(today),
          'to': _date.format(today.add(const Duration(days: 14))),
        });
        return r.data!.map((e) => AbsenceRequest.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> acknowledgeAbsence(String id) => _call(() => _dio.post<void>('absence-requests/$id/acknowledge'));

  // ── NTC-010 설문 ──
  Future<List<ParentSurvey>> surveys() => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/surveys', options: _me);
        return r.data!.map((e) => ParentSurvey.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> submitSurvey(String id, String studentId, Map<String, List<String>> answers) => _call(() => _dio.post<void>('me/surveys/$id/responses', options: _me, data: {
        'studentId': studentId,
        'answers': [for (final e in answers.entries) {'questionId': e.key, 'values': e.value}],
      }));

  // ── NTC-011 앨범 ──
  Future<List<Album>> albums() => _call(() async {
        final r = await _dio.get<List<dynamic>>('me/albums', options: _me, queryParameters: {'limit': 30});
        return r.data!.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<Album> album(String id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('me/albums/$id', options: _me);
        return Album.fromJson(r.data!);
      });

  // ── PAR-008 위치 정보 제공 동의 ──
  Future<bool> locationConsent(String childId) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('me/children/$childId/location-consent', options: _me);
        return r.data!['granted'] as bool;
      });

  Future<bool> setLocationConsent(String childId, bool granted) => _call(() async {
        final r = await _dio.put<Map<String, dynamic>>('me/children/$childId/location-consent', options: _me, data: {'granted': granted});
        return r.data!['granted'] as bool;
      });

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final commRepositoryProvider = Provider<CommRepository>((ref) => CommRepository(ref.watch(apiClientProvider)));

final conversationsProvider = FutureProvider.autoDispose.family<List<Conversation>, bool>((ref, staff) => ref.watch(commRepositoryProvider).conversations(staff: staff));
final myAbsenceRequestsProvider = FutureProvider.autoDispose<List<AbsenceRequest>>((ref) => ref.watch(commRepositoryProvider).myAbsenceRequests());
final staffAbsenceRequestsProvider = FutureProvider.autoDispose<List<AbsenceRequest>>((ref) => ref.watch(commRepositoryProvider).staffAbsenceRequests());
final surveysProvider = FutureProvider.autoDispose<List<ParentSurvey>>((ref) => ref.watch(commRepositoryProvider).surveys());
final albumsProvider = FutureProvider.autoDispose<List<Album>>((ref) => ref.watch(commRepositoryProvider).albums());
final albumDetailProvider = FutureProvider.autoDispose.family<Album, String>((ref, id) => ref.watch(commRepositoryProvider).album(id));
