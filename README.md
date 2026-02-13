# JellyFamily

가족용 "용돈 + 챌린지" 앱입니다.

## 구성

- `jelly_family_app/`: Flutter 클라이언트(자녀/부모)
- `supabase/`: Supabase(Postgres + Storage + Edge Functions) 백엔드
- `scripts/`: 시드/공휴일 데이터 유틸리티(Node)

## 빠른 링크

- 앱 실행 방법: `jelly_family_app/README.md`
- 백엔드/스키마/함수 설명: `readme.txt`

## 보안

- 앱에는 `SUPABASE_URL`, `SUPABASE_ANON_KEY`만 사용합니다.
- `SUPABASE_SERVICE_ROLE_KEY`는 시드/서버에서만 사용해야 하며 앱에 포함하면 안 됩니다.
