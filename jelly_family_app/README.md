# JellyFamily App (Flutter)

가족용 "용돈 + 챌린지" 앱의 Flutter 클라이언트입니다.

## 주요 화면

- 자녀: 지갑(젤리/현금) 확인, 월 챌린지 선택, 젤리 환전, 용돈 요청, 리워드(스페셜/보너스) 수령
- 부모: 자녀 지갑/챌린지 현황 확인, 젤리 지급, 용돈 요청 정산(증빙 업로드)

## Supabase 설정

기본값은 `lib/config/supabase_config.dart`에 들어있고, 런타임에 `--dart-define`으로 오버라이드할 수 있습니다.

```bash
flutter run \
  --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

## 실행

```bash
cd jelly_family_app
flutter pub get
flutter run
```

## 알림

앱 시작 시 로컬 알림을 초기화하고, 매일 오전 6시에 "오늘의 챌린지" 알림을 예약합니다.
(권한/플랫폼 상태에 따라 동작하지 않을 수 있으며, 실패해도 앱은 정상 동작합니다.)
