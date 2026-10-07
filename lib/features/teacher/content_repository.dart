import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../parent/models.dart' show FileAttachment;
import 'content_models.dart';

/// 교사앱 알림장(NTC)·행사(EVT) API. 교사는 본인이 만든 것만 내려온다 (원장·실장은 기관 전체).
class ContentRepository {
  ContentRepository(this._api);

  final ApiClient _api;
  Dio get _dio => _api.dio;

  static const maxFileBytes = 20 * 1024 * 1024;

  // ───────── 알림장 ─────────

  Future<PageOf<TeacherNotice>> notices(int page, {NoticeKind? kind, NoticeStatus? status}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('notices', queryParameters: {
          'page': page,
          'size': 20,
          if (kind != null) 'kind': kind.api,
          if (status != null) 'status': status.api,
        });
        return PageOf.fromJson(r.data!, TeacherNotice.fromJson);
      });

  Future<TeacherNotice> notice(String id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('notices/$id');
        return TeacherNotice.fromJson(r.data!);
      });

  /// 작성 + 즉시/예약 발송. 네트워크 오류면 같은 Idempotency-Key 로 다시 보내 중복 발송을 막는다.
  Future<TeacherNotice> createNotice(NoticeDraft d) =>
      _write((o) => _dio.post<Map<String, dynamic>>('notices', data: d.toJson(), options: o), TeacherNotice.fromJson);

  /// 예약 건 수정 (발송 후엔 불가)
  Future<TeacherNotice> updateNotice(String id, NoticeDraft d) => _call(() async {
        final r = await _dio.patch<Map<String, dynamic>>('notices/$id', data: d.toJson());
        return TeacherNotice.fromJson(r.data!);
      });

  Future<TeacherNotice> cancelNotice(String id) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('notices/$id/cancel');
        return TeacherNotice.fromJson(r.data!);
      });

  Future<NoticeReceipts> receipts(String id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('notices/$id/receipts');
        return NoticeReceipts.fromJson(r.data!);
      });

  /// NTC-006 미열람자만 재푸시. 응답: 대상 원생 수·푸시 받은 보호자 수
  Future<({int students, int pushRecipients})> resendUnread(String id) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('notices/$id/resend-unread');
        return (students: (r.data!['students'] as num).toInt(), pushRecipients: (r.data!['pushRecipients'] as num).toInt());
      });

  // ───────── 행사 ─────────

  Future<PageOf<SchoolEvent>> events({required bool upcoming, required int page}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('events', queryParameters: {'upcoming': upcoming, 'page': page, 'size': 20});
        return PageOf.fromJson(r.data!, SchoolEvent.fromJson);
      });

  Future<SchoolEvent> createEvent(EventDraft d) =>
      _write((o) => _dio.post<Map<String, dynamic>>('events', data: d.toCreateJson(), options: o), SchoolEvent.fromJson);

  Future<SchoolEvent> updateEvent(String id, EventDraft d) => _call(() async {
        final r = await _dio.patch<Map<String, dynamic>>('events/$id', data: d.toUpdateJson());
        return SchoolEvent.fromJson(r.data!);
      });

  Future<SchoolEvent> cancelEvent(String id) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('events/$id/cancel');
        return SchoolEvent.fromJson(r.data!);
      });

  Future<EventSummary> eventSummary(String id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('events/$id/summary');
        return EventSummary.fromJson(r.data!);
      });

  /// EVT-004 수동 독촉 (30분 쿨타임). 응답: 푸시 대상 보호자 수
  Future<int> remindEvent(String id) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('events/$id/remind');
        return (r.data!['pushRecipients'] as num).toInt();
      });

  // ───────── 대상 선택·첨부 ─────────

  /// 이름·보호자 번호 뒷 4자리로 재원생 검색
  Future<List<StudentRef>> searchStudents(String keyword) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('students', queryParameters: {'keyword': keyword, 'status': 'ACTIVE', 'size': 20});
        return (r.data!['items'] as List).map((e) => StudentRef.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// 스펙 8장 파일 흐름: presign → S3 로 직접 PUT → complete. 파일 본문은 API 서버를 거치지 않는다.
  Future<FileAttachment> uploadNoticeImage(XFile picked) => uploadNoticeFile(picked.path, picked.name);

  /// 사진·PDF 공통. 형식은 파일 이름 확장자로 판단한다.
  Future<FileAttachment> uploadNoticeFile(String path, String name) => _call(() async {
        final file = File(path);
        final size = await file.length();
        if (size > maxFileBytes) throw ApiException(400, 'FILE_TOO_LARGE', '20MB 이하 파일만 올릴 수 있습니다');
        final mime = _mimeOf(name);

        final presign = await _dio.post<Map<String, dynamic>>('files/presign', data: {
          'purpose': 'NOTICE_ATTACHMENT',
          'filename': name,
          'mime': mime,
          'size': size,
        });
        final fileId = presign.data!['fileId'] as String;
        final upload = presign.data!['upload'] as Map<String, dynamic>;

        // 서명된 헤더는 서버가 준 그대로 보낸다 (Content-Type 이 서명에 들어 있을 수 있음)
        final headers = <String, dynamic>{
          for (final e in ((upload['headers'] as Map?) ?? const {}).entries) e.key.toString(): e.value is List ? (e.value as List).join(',') : e.value.toString(),
          Headers.contentLengthHeader: size.toString(),
        };
        final hasContentType = headers.keys.any((k) => k.toLowerCase() == 'content-type');
        try {
          await Dio().request<void>(
            upload['url'] as String,
            data: file.openRead(),
            options: Options(method: (upload['method'] as String?) ?? 'PUT', headers: headers, contentType: hasContentType ? null : mime),
          );
        } on DioException catch (e) {
          if (e.response == null) rethrow; // 네트워크 오류는 공통 메시지로
          throw ApiException(e.response!.statusCode, 'UPLOAD_FAILED', '파일 업로드에 실패했습니다 (${e.response!.statusCode})');
        }

        final done = await _dio.post<Map<String, dynamic>>('files/$fileId/complete');
        return FileAttachment.fromJson(done.data!);
      });

  static String _mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  /// 같은 키로 최대 3번 (0.5s, 1s 간격). 서버가 같은 키를 이미 처리했으면 그 결과를 돌려준다.
  Future<T> _write<T>(Future<Response<Map<String, dynamic>>> Function(Options) send, T Function(Map<String, dynamic>) parse) async {
    final key = ApiClient.newIdempotencyKey();
    for (var attempt = 0;; attempt++) {
      try {
        final r = await send(Options(headers: {'Idempotency-Key': key}));
        return parse(r.data!);
      } catch (e) {
        final err = ApiException.from(e);
        if (!err.isNetwork || attempt >= 2) throw err;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final contentRepositoryProvider = Provider<ContentRepository>((ref) => ContentRepository(ref.watch(apiClientProvider)));
