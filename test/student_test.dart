import 'package:flutter_test/flutter_test.dart';
import 'package:ttokttok_app/features/student/student_api.dart';

void main() {
  test('CHECKED_IN 응답', () {
    final r = ScanResult.fromJson({'outcome': 'CHECKED_IN', 'classroomName': '초등 수학 A'});
    expect(r.outcome, ScanOutcome.checkedIn);
    expect(r.classroomName, '초등 수학 A');
    expect(r.destinations, isEmpty);
  });

  test('CHOOSE_DESTINATION 은 목적지 목록을 준다', () {
    final r = ScanResult.fromJson({
      'outcome': 'CHOOSE_DESTINATION',
      'destinations': [
        {'id': 'd1', 'name': '집', 'type': 'HOME'},
        {'id': 'd2', 'name': '영어학원', 'type': 'ACADEMY'},
      ],
    });
    expect(r.outcome, ScanOutcome.chooseDestination);
    expect(r.destinations.map((d) => d.name), ['집', '영어학원']);
  });

  test('모르는 outcome 은 alreadyDone', () {
    expect(ScanResult.fromJson({'outcome': 'ALREADY_DONE'}).outcome, ScanOutcome.alreadyDone);
  });
}
