import 'package:flutter_test/flutter_test.dart';
import 'package:ttokttok_app/core/push/push_service.dart';

void main() {
  test('로컬 알림 payload 는 data 를 그대로 왕복한다', () {
    const p = PushPayload({'type': 'notice', 'noticeId': 'n-1', 'kind': 'NOTICE'});
    final back = PushPayload.decode(p.encode());
    expect(back.type, 'notice');
    expect(back.data['noticeId'], 'n-1');
  });

  test('숫자 값도 문자열로 읽는다', () {
    final p = PushPayload.decode('{"type":"attendance","studentId":"s-1","count":3}');
    expect(p.data['count'], '3');
  });
}
