import 'package:flutter_test/flutter_test.dart';
import 'package:ttokttok_app/features/parent/models.dart';

void main() {
  TimelineItem item(String type, String status, {bool late = false, String? dest}) => TimelineItem.fromJson({
        'studentId': 's1', 'studentName': '김하늘', 'institutionId': 'i1', 'institutionName': '똑똑수학',
        'type': type, 'status': status, 'isLate': late, 'destinationName': dest, 'occurredAt': '2026-10-06T06:00:00Z',
      });

  test('타임라인 문장', () {
    expect(item('CHECK_IN', 'IN').headline, '똑똑수학에 도착했어요');
    expect(item('CHECK_IN', 'IN', late: true).headline, '똑똑수학에 도착했어요 (지각)');
    expect(item('CHECK_OUT', 'OUT', dest: '셔틀 1호차').headline, '똑똑수학에서 출발했어요 → 셔틀 1호차');
    expect(item('STATUS_CHANGE', 'ABSENT').headline, '똑똑수학 결석으로 처리됐어요');
  });

  test('수업 시각 표시: LocalTime 과 ISO 모두', () {
    expect(ScheduleItem.hm('14:00'), '14:00');
    expect(ScheduleItem.hm('14:00:00'), '14:00');
  });

  test('행사 응답 필요 여부', () {
    final e = ParentEvent.fromJson({
      'id': 'e1', 'institutionId': 'i1', 'institutionName': '똑똑수학', 'title': '가을 소풍', 'startsAt': '2026-10-20T01:00:00Z',
      'status': 'ACTIVE', 'rsvpEnabled': true, 'open': true,
      'children': [{'studentId': 's1', 'name': '김하늘', 'answer': null}],
    });
    expect(e.needsAnswer, true);
  });

  test('아이 하나가 여러 기관 (스펙 7-8)', () {
    final c = Child.fromJson({
      'childId': 'c1',
      'name': '김하늘',
      'enrollments': [
        {'studentId': 's1', 'studentName': '김하늘', 'institutionId': 'i1', 'institutionName': '똑똑수학', 'institutionType': 'ACADEMY', 'status': 'ACTIVE'},
        {'studentId': 's2', 'studentName': '김 하늘', 'institutionId': 'i2', 'institutionName': '한빛초', 'institutionType': 'SCHOOL', 'status': 'ACTIVE'},
      ],
    });
    expect(c.institutionsLabel, '똑똑수학 · 한빛초');
    expect(c.hasStudent('s2'), isTrue);
    expect(c.enrollments[1].typeLabel, '학교');
  });

  test('합치기 후보 키는 순서와 상관없다', () {
    final a = MergeSuggestion.fromJson({'childIds': ['b', 'a'], 'name': '김하늘', 'institutionNames': ['A', 'B']});
    final b = MergeSuggestion.fromJson({'childIds': ['a', 'b'], 'name': '김하늘', 'institutionNames': ['A', 'B']});
    expect(a.key, b.key);
  });
}
