````md
# 젤리패밀리 (JellyFamily) — App + Supabase 백엔드 README
가족용 “용돈 + 챌린지” 앱.
- 자녀: 챌린지 진행 → 젤리 보유 → 젤리→원 교환 → 용돈 요청
- 부모: 06:00~08:00만 젤리 지급(당일 원칙 + 1일 지연 허용) → 용돈 지급 후 증빙(캡쳐) 업로드 → 자녀 보유금액 0원 정산(이미지 자녀도 열람)

> **핵심 원칙:** 랜덤 환전/시간 제한/정산(0원) 같은 룰은 **클라이언트가 아니라 서버(Edge Function)에서 강제**해야 함.

---

## 0) 기술 선택(권장)
- Backend: **Supabase** (Postgres + Auth + Storage + Edge Functions)
- Timezone: **Asia/Seoul**
- Client(App): Flutter / React Native(Expo) / Kotlin/Swift 모두 가능  
  (이 README는 프레임워크-무관하게 “백엔드 자동 구현”에 초점)

---

## 1) 로그인 설계(MVP: 드롭다운 + PIN)
요구사항: 로그인 화면에서 “이름 선택(콤보박스)” + “비밀번호(PIN)” 입력.

### 추천 구현(가장 단순 + RLS 친화)
- Supabase Auth의 이메일/비밀번호 로그인 사용
- 앱에는 “이름-이메일” 매핑을 **상수로 내장**하고, PIN을 Auth password로 사용
  - 예) 이원형 → `wonhyung@jelly.family` / PW=7470

앱에서:
- 드롭다운으로 이름 선택
- 해당 이름의 email을 가져와 `signInWithPassword(email, pin)` 호출

> 장점: RLS에서 `auth.uid()`를 그대로 쓰며, 커스텀 세션/보안 설계가 필요 없어짐.

---

## 2) 사용자 계정(시드)
| 이름 | 역할(권장) | 로그인 이메일 | PIN(패스워드) |
|---|---|---|---|
| 이원형 | PARENT | wonhyung@jelly.family | 7470 |
| 박설화 | PARENT | seolhwa@jelly.family | 5373 |
| 이진아 | CHILD | jina@jelly.family | 2132 |
| 이진오 | CHILD | jino@jelly.family | 2174 |
| 이진서 | CHILD | jinseo@jelly.family | 0000 |

---

## 3) 로컬/개발 환경 준비
### 3.1 Supabase 프로젝트 생성
- Supabase에서 새 프로젝트 생성

### 3.2 Supabase CLI 설치 & 초기화
```bash
npm i -g supabase
supabase login
supabase init
supabase link --project-ref <YOUR_PROJECT_REF>
````

### 3.3 환경변수

#### (서버/스크립트용) `.env`

```bash
SUPABASE_URL="https://gbzkrbepxejjcffyohcb.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiemtyYmVweGVqamNmZnlvaGNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2ODkzMjQsImV4cCI6MjA4NTI2NTMyNH0.UVfArhZQB4cUw-em0IvYbgCKbSPFXA5jnMjI0emNldE"
SUPABASE_SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiemtyYmVweGVqamNmZnlvaGNiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2OTY4OTMyNCwiZXhwIjoyMDg1MjY1MzI0fQ.qEBoaswM7s_AyL4vVrq0FHeLW4sydh3DJb0p3SKs6-0"  # seed & signed-url 함수에서만 사용 (절대 앱에 포함 금지)
APP_TIMEZONE="Asia/Seoul"
```

#### (앱용)

* 앱에는 `SUPABASE_URL`, `SUPABASE_ANON_KEY`만 넣기
* `SERVICE_ROLE_KEY`는 절대 앱에 넣지 않기

---

## 4) DB 스키마(SQL) + RLS (자동 구축)

아래 파일을 만들어 마이그레이션으로 적용하세요.

### 4.1 `supabase/migrations/0001_init.sql`

```sql
-- extensions
create extension if not exists pgcrypto;

-- enums
do $$ begin
  create type public.user_role as enum ('PARENT', 'CHILD');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.jelly_type as enum ('NORMAL', 'SPECIAL', 'BONUS');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.challenge_type as enum ('BOOK_READING', 'ARITHMETIC', 'HANJA_WRITING');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.allowance_status as enum ('REQUESTED', 'PROOF_UPLOADED', 'SETTLED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.day_status as enum ('PENDING', 'DONE', 'REWARDED');
exception when duplicate_object then null; end $$;

-- profiles: auth.users(id)와 1:1
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.user_role not null,
  created_at timestamptz not null default now()
);

-- wallets: 사용자별 젤리/현금 보유
create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  jelly_normal int not null default 0 check (jelly_normal >= 0),
  jelly_special int not null default 0 check (jelly_special >= 0),
  jelly_bonus int not null default 0 check (jelly_bonus >= 0),
  cash_balance int not null default 0 check (cash_balance >= 0),
  updated_at timestamptz not null default now()
);

-- 월별 챌린지(2개 선택)
create table if not exists public.challenge_months (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  year_month text not null, -- 'YYYY-MM'
  challenge_a public.challenge_type not null,
  challenge_b public.challenge_type not null,
  pair_key text not null,   -- 정렬 후 'A|B'
  created_at timestamptz not null default now(),
  unique (child_id, year_month)
);

create index if not exists idx_challenge_months_child_month on public.challenge_months(child_id, year_month);

-- 달력용 일별 상태
create table if not exists public.challenge_days (
  id uuid primary key default gen_random_uuid(),
  challenge_month_id uuid not null references public.challenge_months(id) on delete cascade,
  day_date date not null,
  status public.day_status not null default 'PENDING',
  memo text,
  created_at timestamptz not null default now(),
  unique (challenge_month_id, day_date)
);

-- 부모 젤리 지급 로그
create table if not exists public.jelly_grants (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid not null references public.profiles(id) on delete cascade,
  challenge public.challenge_type not null,
  target_date date not null, -- 수행 기준일
  jelly public.jelly_type not null,
  amount int not null check (amount > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_jelly_grants_child_date on public.jelly_grants(child_id, target_date);

-- 젤리->원 교환 로그
create table if not exists public.jelly_exchanges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  jelly public.jelly_type not null,
  amount int not null check (amount > 0),
  exchanged_cash int not null check (exchanged_cash > 0),
  created_at timestamptz not null default now()
);

-- 용돈 요청
create table if not exists public.allowance_requests (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  requested_cash int not null check (requested_cash >= 0),
  status public.allowance_status not null default 'REQUESTED',
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create index if not exists idx_allowance_requests_child on public.allowance_requests(child_id, created_at desc);

-- 증빙(이미지 경로)
create table if not exists public.allowance_proofs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.allowance_requests(id) on delete cascade,
  uploader_parent_id uuid not null references public.profiles(id) on delete cascade,
  object_path text not null, -- Storage path
  created_at timestamptz not null default now()
);

-- helper views (필요 시)
create or replace view public.v_me as
select p.id, p.display_name, p.role
from public.profiles p
where p.id = auth.uid();

-- -------- RLS --------
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.challenge_months enable row level security;
alter table public.challenge_days enable row level security;
alter table public.jelly_grants enable row level security;
alter table public.jelly_exchanges enable row level security;
alter table public.allowance_requests enable row level security;
alter table public.allowance_proofs enable row level security;

-- profiles: 본인 읽기 + 부모는 전체 읽기
create policy "profiles: self select"
on public.profiles for select
to authenticated
using (id = auth.uid());

create policy "profiles: parent select all"
on public.profiles for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

-- wallets: 본인 읽기/업데이트 + 부모는 자녀 지갑 읽기
create policy "wallets: self select"
on public.wallets for select
to authenticated
using (user_id = auth.uid());

create policy "wallets: parent select"
on public.wallets for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

create policy "wallets: self update"
on public.wallets for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- challenge_months: 자녀 본인 CRUD(월 선택은 함수로만 해도 됨) + 부모 조회
create policy "challenge_months: child select own"
on public.challenge_months for select
to authenticated
using (child_id = auth.uid());

create policy "challenge_months: parent select all"
on public.challenge_months for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

-- challenge_days: child/parent 조회
create policy "challenge_days: child select own"
on public.challenge_days for select
to authenticated
using (
  exists (
    select 1
    from public.challenge_months cm
    where cm.id = challenge_month_id
      and cm.child_id = auth.uid()
  )
);

create policy "challenge_days: parent select"
on public.challenge_days for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

-- jelly_grants: 자녀는 본인 조회, 부모는 insert/조회
create policy "jelly_grants: child select own"
on public.jelly_grants for select
to authenticated
using (child_id = auth.uid());

create policy "jelly_grants: parent select"
on public.jelly_grants for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

create policy "jelly_grants: parent insert"
on public.jelly_grants for insert
to authenticated
with check (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

-- jelly_exchanges: 본인 조회/insert, 부모 조회
create policy "jelly_exchanges: self select"
on public.jelly_exchanges for select
to authenticated
using (user_id = auth.uid());

create policy "jelly_exchanges: self insert"
on public.jelly_exchanges for insert
to authenticated
with check (user_id = auth.uid());

create policy "jelly_exchanges: parent select"
on public.jelly_exchanges for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

-- allowance_requests: 자녀 본인 CRUD 일부 + 부모 조회/정산은 함수에서
create policy "allowance_requests: child select own"
on public.allowance_requests for select
to authenticated
using (child_id = auth.uid());

create policy "allowance_requests: child insert own"
on public.allowance_requests for insert
to authenticated
with check (child_id = auth.uid());

create policy "allowance_requests: parent select"
on public.allowance_requests for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

-- allowance_proofs: 자녀(해당 요청의 child)와 부모 모두 조회, insert는 부모만(함수에서 주로)
create policy "allowance_proofs: child select own"
on public.allowance_proofs for select
to authenticated
using (
  exists (
    select 1 from public.allowance_requests ar
    where ar.id = request_id and ar.child_id = auth.uid()
  )
);

create policy "allowance_proofs: parent select"
on public.allowance_proofs for select
to authenticated
using (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);

create policy "allowance_proofs: parent insert"
on public.allowance_proofs for insert
to authenticated
with check (
  exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.role = 'PARENT')
);
```

### 4.2 마이그레이션 적용

```bash
supabase db push
```

---

## 5) Storage 버킷(증빙 이미지)

* 버킷명: `allowance-proofs`
* Public: **OFF (private)**

### 권장 패턴(가장 안전)

* 앱은 이미지를 Storage에 업로드(부모만) → 업로드된 `object_path`를 함수로 전달
* 자녀/부모가 이미지를 볼 때는 **Edge Function에서 signed URL 생성**해 반환
  (Storage 정책을 복잡하게 짜는 대신, 서버에서 권한 체크 후 signed URL만 발급)

---

## 6) Edge Functions (서버 룰 강제)

> 아래 함수들로 “시간 제한 / 랜덤 환전 / 정산 0원 / 조합 제한”을 전부 서버에서 처리.

### 6.1 생성할 함수 목록

* `select-challenges` : 월 챌린지 2개 선택(전월 동일 조합 금지) + 달력일 생성
* `grant-jelly` : 부모 젤리 지급(06~08, 당일/1일지연) + wallet 업데이트 + 로그
* `exchange-jelly` : 젤리→원 교환(랜덤은 서버 결정) + wallet 업데이트 + 로그
* `request-allowance` : 자녀 용돈 요청 생성(기본값=현재 cash_balance 추천)
* `upload-proof-and-settle` : 부모 증빙 등록 + 자녀 cash_balance=0 + 요청 SETTLED
* `get-proof-url` : 권한 체크 후 signed URL 발급(부모/해당 자녀만)

### 6.2 함수 스캐폴딩

```bash
supabase functions new select-challenges
supabase functions new grant-jelly
supabase functions new exchange-jelly
supabase functions new request-allowance
supabase functions new upload-proof-and-settle
supabase functions new get-proof-url
```

### 6.3 배포

```bash
supabase functions deploy select-challenges
supabase functions deploy grant-jelly
supabase functions deploy exchange-jelly
supabase functions deploy request-allowance
supabase functions deploy upload-proof-and-settle
supabase functions deploy get-proof-url
```

> 함수는 기본적으로 JWT 검증(verify-jwt)이 켜져야 합니다(로그인 유저만 호출).

---

## 7) 시드(계정 자동 생성) — Auth + profiles + wallets

Supabase Auth 유저 생성은 SQL만으로 끝내기 어렵습니다.
→ **Service Role Key**를 사용하는 스크립트로 자동 생성하세요.

### 7.1 `scripts/seed.mjs` (예시)

```js
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) throw new Error('Missing env')

const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })

const users = [
  { email: 'wonhyung@jelly.family', password: '7470', display_name: '이원형', role: 'PARENT' },
  { email: 'seolhwa@jelly.family',  password: '5373', display_name: '박설화', role: 'PARENT' },
  { email: 'jina@jelly.family',    password: '2132', display_name: '이진아', role: 'CHILD' },
  { email: 'jino@jelly.family',    password: '2174', display_name: '이진오', role: 'CHILD' },
  { email: 'jinseo@jelly.family',  password: '0000', display_name: '이진서', role: 'CHILD' },
]

for (const u of users) {
  // 1) auth user create
  const { data: created, error: e1 } = await supabase.auth.admin.createUser({
    email: u.email,
    password: u.password,
    email_confirm: true,
  })
  if (e1 && !String(e1.message).includes('already registered')) throw e1

  // find user id
  const { data: list, error: e2 } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 })
  if (e2) throw e2
  const found = list.users.find(x => x.email === u.email)
  if (!found) throw new Error('User not found after create: ' + u.email)

  // 2) profile upsert
  const { error: e3 } = await supabase.from('profiles').upsert({
    id: found.id,
    display_name: u.display_name,
    role: u.role,
  })
  if (e3) throw e3

  // 3) wallet upsert
  const { error: e4 } = await supabase.from('wallets').upsert({
    user_id: found.id,
    jelly_normal: 0,
    jelly_special: 0,
    jelly_bonus: 0,
    cash_balance: 0,
  })
  if (e4) throw e4
}

console.log('✅ seed done')
```

### 7.2 실행

```bash
npm i @supabase/supabase-js dotenv
node scripts/seed.mjs
```

---

## 8) 앱에서 Supabase API “미리 연결” (초기 설정)

### 8.1 공통(권장)

* 앱 시작 시 Supabase client를 싱글톤으로 초기화
* 로그인 성공 후 `auth.uid()` 기반으로 모든 데이터는 RLS로 자동 필터링

### 8.2 React Native / Expo (supabase-js)

```ts
import { createClient } from '@supabase/supabase-js'

export const supabase = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL!,
  process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!
)
```

### 8.3 Flutter (supabase_flutter)

```dart
await Supabase.initialize(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
```

---

## 9) 서버 룰(요구사항) 체크리스트 — Codex가 반드시 구현해야 할 것

### A. 젤리 환전(랜덤 서버결정)

* NORMAL/BONUS: 5~15원
* SPECIAL: 90~150원
* 트랜잭션: wallet 젤리 차감 → cash_balance 증가 → exchange 로그

### B. 부모 젤리 지급 시간 제한

* 서버에서 **Asia/Seoul** 기준으로 판단
* 06:00~08:00만 허용
* target_date는 **오늘 또는 어제**만 허용(1일 지연)

### C. 용돈 요청 & 정산(0원)

* 자녀 요청 생성
* 부모가 증빙 업로드 후 `upload-proof-and-settle` 호출:

  * proof insert
  * request status SETTLED
  * child wallet.cash_balance = 0
  * 이미 정산된 요청이면 재실행 방지(idempotent)

### D. 월 챌린지(2개 선택) + 전월 동일 조합 금지

* 2개는 서로 달라야 함
* pair_key = 정렬 후 `A|B`
* 이번 달 pair_key == 전월 pair_key면 거부
* 선택 완료 시 해당 월의 달력 day row 생성(최소 PENDING)

### E. 증빙 이미지 접근

* 버킷은 private
* 이미지는 `get-proof-url`로 signed URL 발급
* 권한: 부모 or 해당 자녀만

---

## 10) “Codex에게 그대로 붙여넣는” 구현 지시문(권장)

아래를 Codex에 전달해서 자동 구현 범위를 명확히 하세요.

* Supabase 프로젝트를 백엔드로 사용한다.
* DB는 migrations/0001_init.sql 그대로 적용한다.
* Edge Functions 6개(select-challenges, grant-jelly, exchange-jelly, request-allowance, upload-proof-and-settle, get-proof-url)를 구현한다.
* 함수 내부에서 Asia/Seoul 시간 기준으로 지급 가능 시간(06:00~08:00)과 1일 지연 허용을 강제한다.
* 젤리 환전 랜덤은 서버에서만 결정한다.
* 증빙 업로드 후 자녀 cash_balance를 0으로 만들고, 자녀도 증빙을 볼 수 있도록 signed URL 제공 함수를 만든다.
* 로그인은 Supabase Auth 이메일/비번으로 처리하고, 앱 UI는 드롭다운 이름 선택 + PIN 입력으로 signInWithPassword를 호출한다(이메일 매핑은 앱 상수로 둔다).
* 시드 스크립트 scripts/seed.mjs로 위 5명 계정을 생성하고 profiles/wallets를 upsert한다.

---

## 11) 운영 팁(최소)

* **SERVICE_ROLE_KEY는 서버/CI에서만 사용**(절대 앱에 넣지 말 것)
* 모든 “돈/랜덤/정산” 로직은 Edge Functions에서 처리
* 앱은 함수 호출 + 표시만 담당(치트 방지)

---

```

원하면 다음 단계로, 내가 **Edge Function 6개에 대한 “정확한 입력/출력(JSON 스키마)”**까지 README에 붙여서 Codex가 더 실수 없이 구현하도록 만들어줄게. (예: `grant-jelly` 요청 body, 에러 코드, 성공 응답 형태 등)
::contentReference[oaicite:0]{index=0}
```
