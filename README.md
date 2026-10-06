# 똑똑(Ttok-Ttok) 앱 — 교사·학부모

스펙: 교사앱·학부모앱 = 하나의 코드베이스, flavor 2개. Flutter 3 · Riverpod · Dio · go_router · flutter_secure_storage · STOMP.
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

# 학부모앱 (지금은 로그인·자녀 연결 확인만)
flutter run -t lib/main_parent.dart
```

스토어용 네이티브 flavor(패키지명·아이콘·스킴 분리)는 배포 준비 때 `android/app/build.gradle` productFlavors 와 iOS scheme 으로 추가한다 (스펙 9장: teacher/parent × dev/prod).

## 구조

```
lib/
  main_teacher.dart / main_parent.dart   진입점 (flavor)
  bootstrap.dart                         저장된 세션 복원 → 앱 시작
  app/        flavor·환경(--dart-define), 테마, 라우터(로그인·비번 강제 변경·기관 선택 redirect)
  core/
    api/      Dio 클라이언트: access 만료 임박·401 → refresh(한 번에 하나) 후 재시도, X-Institution-Id
    auth/     토큰 저장(flutter_secure_storage), 로그인 상태(Riverpod Notifier)
    realtime/ STOMP — 끊기면 5초 뒤 새 토큰으로 재연결
    widgets/  상태 배지 (관리자 웹과 같은 라벨 규칙)
  features/
    auth/     AUTH-001 로그인, 기관 선택, AUTH-005 비밀번호 변경(임시 비번이면 강제)
    teacher/  담당 반 목록 → 반 출결: ATT-005 원터치 등원, ATT-006 하원+목적지, ATT-002 수동 변경(길게 누름)
    parent/   (다음 단계) PAR-001 타임라인, PAR-004 알림장함, PAR-005 행사 응답
```

## 출결 원터치 동작

- 누르면 화면이 바로 바뀌고(낙관적), 서버가 거절하면 되돌린 뒤 스낵바로 알린다.
- 등·하원 요청마다 `Idempotency-Key` 와 `clientAt` 을 붙인다. 응답을 못 받으면(오프라인·타임아웃) **같은 키로** 최대 3번 재시도 — 서버가 중복 처리하지 않는다.
- 같은 반을 보는 다른 교사·관리자 웹의 변경은 `/topic/class.{반}` 으로 들어와 해당 행만 바뀐다. 앱이 다시 앞으로 오면 목록을 새로 읽는다.
- 잘못 누른 등원은 ⋮ 또는 길게 눌러 수동 변경 (사유 필수, 학부모에게 정정 푸시 없음).

## 아직 안 한 것

- 푸시(FCM): Firebase 프로젝트 설정 후 토큰을 `PUT /api/v1/me/devices {flavor, platform, token}` 로 등록 (`bootstrap.dart` TODO)
- 오프라인 큐: 지금은 즉시 재시도만. 장시간 오프라인은 `POST /attendance/bulk` 로 모아 보내는 방식 검토
- 교사앱 알림장 작성·행사(NTC/EVT 교사 기능), 학부모앱 전체
- 스펙의 Retrofit·freezed 대신 코드 생성 없이 Dio + 손으로 쓴 모델 (빌드 단계를 줄이려고). 필요하면 나중에 전환
