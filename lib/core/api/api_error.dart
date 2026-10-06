import 'package:dio/dio.dart';

/// 백엔드 오류 {code, message, details} 를 화면에서 쓰기 좋게
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int? status;
  final String code;
  final String message;

  /// 응답을 못 받은 경우 (오프라인·타임아웃) — 같은 Idempotency-Key 로 다시 보내도 안전
  bool get isNetwork => status == null;

  factory ApiException.from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final res = e.response;
      if (res == null) {
        return ApiException(null, 'NETWORK', '네트워크에 연결할 수 없습니다. 잠시 후 다시 시도하세요');
      }
      final data = res.data;
      if (data is Map) {
        return ApiException(
          res.statusCode,
          (data['code'] ?? 'ERROR').toString(),
          (data['message'] ?? '요청에 실패했습니다 (${res.statusCode})').toString(),
        );
      }
      return ApiException(res.statusCode, 'ERROR', '요청에 실패했습니다 (${res.statusCode})');
    }
    return ApiException(null, 'UNKNOWN', '알 수 없는 오류가 발생했습니다');
  }

  @override
  String toString() => message;
}

String errorMessage(Object e) => ApiException.from(e).message;
