# 똑똑(Ttok-Ttok) 앱 — 교사·학부모·학생

스펙: 교사앱·학부모앱·학생앱(QR 출석) = 하나의 코드베이스, flavor 3개. Flutter 3 · Riverpod · Dio · go_router · flutter_secure_storage · STOMP.
백엔드는 `ttokttok_edu_backend`, 관리자 웹은 `ttokttok_edu_react`.

## 처음 한 번

이 폴더에는 `lib/`·`test/`·`pubspec.yaml` 만 있다. 플랫폼 폴더(android/ios)는 Flutter 로 만든다 — 기존 파일은 덮지 않는다.

```bash
flutter create --org app.ttok --project-name ttokttok_app --platforms android,ios .
flutter pub get
```

안드로이드에서 로컬 백엔드(http)를 쓰려면 `android/app/src/main/AndroidManifest.xml` 의 `<application>` 에
`android:usesCleartextTraffic="true"` 를 넣는다 (개발용).

## 실행

```bash
# 교사앱 (에뮬레이터: PC localhost = 10.0.2.2, 기본값)
flutter run -t lib/main_teacher.dart

# 실기기 / 다른 서버
flutter run -t lib/main_teacher.dart --dart-define=API_BASE_URL=http://192.168.0.10:8080 --dart-define=WS_URL=ws://192.168.0.10:8080/ws

# 학부모앱
flutter run -t lib/main_parent.dart

# 학생앱 (QR 출석 — 카메라·위치가 필요해 실기기 권장)
flutter run -t lib/main_student.dart --dart-define=API_BASE_URL=http://192.168.0.10:8080
```

스토어용 네이티브 flavor(패키지명·아이콘·스킴 분리)는 배포 준비 때 `android/app/build.gradle` productFlavors 와 iOS scheme 으로 추가한다 (스펙 9장: teacher/parent × dev/prod).

## 구조

```
lib/
  main_teacher.dart / main_parent.dart / main_student.dart   진입점 (flavor)
  bootstrap.dart                         저장된 세션(학생앱은 기기 토큰) 복원 → 앱 시작
  app/        flavor·환경(--dart-define), 테마, 라우터(로그인·비번 강제 변경·기관 선택 redirect)
  core/
    api/      Dio 클라이언트: access 만료 임박·401 → refresh(한 번에 하나) 후 재시도, X-Institution-Id
    auth/     토큰 저장(flutter_secure_storage), 로그인 상태(Riverpod Notifier)
    realtime/ STOMP — 끊기면 5초 뒤 새 토큰으로 재연결
    widgets/  상태 배지 (관리자 웹과 같은 라벨 규칙)
  features/
    auth/     AUTH-001 로그인, 기관 선택, AUTH-005 비밀번호 변경(임시 비번이면 강제)
    teacher/  담당 반 목록 → 반 출결: ATT-005 원터치 등원, ATT-006 하원+목적지, ATT-002 수동 변경(길게 누름)
    parent/   하단 탭: PAR-001 안심 타임라인 · PAR-004 알림장함(상세 진입 = 열람) · PAR-003 주간 일정 + PAR-005 행사 참석 응답 · 더보기
              가입(보호자 번호 → 자녀 자동 연결 + 학부모 약관 동의), 약관 재동의 게이트, 자녀 선택(전체/자녀별)
              PAR-007 더보기 → 자녀별 "학생앱 연결": 8자리 코드(10분) + 연결 기기 목록·해제
    student/  STD-001 연결 코드 입력 → 기기 토큰(X-Device-Token) · STD-002 홈(오늘 수업) + QR 스캔(위치 첨부)
```

## 출결 원터치 동작

- 누르면 화면이 바로 바뀌고(낙관적), 서버가 거절하면 되돌린 뒤 스낵바로 알린다.
- 등·하원 요청마다 `Idempotency-Key` 와 `clientAt` 을 붙인다. 응답을 못 받으면(오프라인·타임아웃) **같은 키로** 최대 3번 재시도 — 서버가 중복 처리하지 않는다.
- 같은 반을 보는 다른 교사·관리자 웹의 변경은 `/topic/class.{반}` 으로 들어와 해당 행만 바뀐다. 앱이 다시 앞으로 오면 목록을 새로 읽는다.
- 잘못 누른 등원은 ⋮ 또는 길게 눌러 수동 변경 (사유 필수, 학부모에게 정정 푸시 없음).

## 학생 QR 출석 (스펙 7-7)

- 학생은 계정이 없다. 보호자가 학부모앱에서 만든 8자리 코드로 기기를 연결하면 서버가 기기 토큰을 준다 (서버엔 해시만, 자녀당 최대 3대).
- 학원 입구의 고정 QR(관리자 웹 → 출석 QR 에서 생성·출력)을 찍으면 위치와 함께 `POST /api/v1/student/scan`.
  서버가 수업 시간·등원 여부로 등원/하원을 정한다. 하원 목적지가 여러 개면 `CHOOSE_DESTINATION` → 고른 뒤 새 키로 다시 보낸다.
- 실패 코드(422): `QR_INVALID`(재발급된 옛 QR) · `NOT_ENROLLED` · `OUT_OF_RANGE`(지오펜스 밖) · `NO_CLASS_NOW` · `LOCATION_REQUIRED`.
- 권한: Android `CAMERA`·`ACCESS_FINE_LOCATION`, iOS `NSCameraUsageDescription`·`NSLocationWhenInUseUsageDescription`.

## 아직 안 한 것

- 학생앱 스토어 분리 빌드(별도 패키지명·아이콘) — 지금은 진입점만 다르다

- 푸시(FCM): Firebase 프로젝트 설정 후 토큰을 `PUT /api/v1/me/devices {flavor, platform, token}` 로 등록 (`bootstrap.dart` TODO)
- 오프라인 큐: 지금은 즉시 재시도만. 장시간 오프라인은 `POST /attendance/bulk` 로 모아 보내는 방식 검토
- 교사앱 알림장 작성·행사(NTC/EVT 교사 기능)
- 학부모 실시간: 백엔드 /user/queue 가 아직 없어 앱이 앞으로 올 때·당겨서 새로고침으로 갱신 (푸시가 붙으면 푸시 수신 시 갱신)
- 첨부 PDF 열기: url_launcher 추가 전까지 링크 복사. 이미지는 바로 표시
- 휴대폰 SMS 인증(Open Issue 1), 초대 링크 웹 화면(/join/{token})
- 스펙의 Retrofit·freezed 대신 코드 생성 없이 Dio + 손으로 쓴 모델 (빌드 단계를 줄이려고). 필요하면 나중에 전환
