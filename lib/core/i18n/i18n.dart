import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';

/// SET-007 다국어 (한국어·영어). 한국어 문구를 키로 쓰고 영어 사전에 있는 것만 바꾼다.
/// 아직 옮기지 않은 화면·서버 안내 문구는 한국어로 보인다. 화면을 옮길 때 [_en] 에 문구만 더하면 된다.
const _prefKey = 'ui_locale';

const Map<String, String> _en = {
  // 학부모 탭
  '홈': 'Home', '알림장': 'Notices', '일정': 'Schedule', '더보기': 'More', '우리 아이': 'My kids', '일정·행사': 'Schedule & events',
  // 교사 탭
  '출결': 'Attendance', '행사': 'Events', '메시지': 'Messages', '신청': 'Requests',
  // 더보기
  '결석·지각 신청': 'Absence requests', '설문': 'Surveys', '앨범': 'Albums', '상담 예약': 'Consultations', '상담 기록': 'Counseling notes',
  '주간 시간표': 'Weekly timetable', '셔틀 위치': 'Shuttle location', '납부 내역': 'Payments', '비밀번호 변경': 'Change password',
  '간편 로그인 연결': 'Social login', '로그아웃': 'Log out', '언어': 'Language', '한국어': '한국어', 'English': 'English',
  '불러오지 못했습니다': 'Could not load',
  // 행사 후기
  '행사 사진': 'Event photos', '후기': 'Reviews', '후기 남기기': 'Write a review', '수정': 'Edit', '삭제': 'Delete', '취소': 'Cancel',
};

String translate(String ko, String locale) => locale == 'en' ? (_en[ko] ?? ko) : ko;

class LocaleController extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'ko';
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_prefKey);
      if (v == 'en' || v == 'ko') state = v!;
    } catch (_) {}
  }

  /// 기기에 저장하고, 로그인돼 있으면 계정(/me/locale)에도 저장한다 (실패는 무시)
  Future<void> set(String code) async {
    if (code != 'en' && code != 'ko') return;
    state = code;
    try {
      (await SharedPreferences.getInstance()).setString(_prefKey, code);
    } catch (_) {}
    try {
      await ref.read(apiClientProvider).dio.put<void>('me/locale', data: {'locale': code}, options: Options(extra: {'noInstitution': true}));
    } catch (_) {}
  }
}

final localeProvider = NotifierProvider<LocaleController, String>(LocaleController.new);

extension TrRef on WidgetRef {
  /// 화면 언어에 맞춘 문구 (build 안에서 쓰면 언어가 바뀔 때 다시 그린다)
  String t(String ko) => translate(ko, watch(localeProvider));
}

Locale materialLocale(String code) => code == 'en' ? const Locale('en', 'US') : const Locale('ko', 'KR');
