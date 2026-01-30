-- extensions
create extension if not exists pgcrypto;

-- enums
DO $$ BEGIN
  create type public.user_role as enum ('PARENT', 'CHILD');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  create type public.jelly_type as enum ('NORMAL', 'SPECIAL', 'BONUS');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  create type public.challenge_type as enum ('BOOK_READING', 'ARITHMETIC', 'HANJA_WRITING');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  create type public.allowance_status as enum ('REQUESTED', 'PROOF_UPLOADED', 'SETTLED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  create type public.day_status as enum ('PENDING', 'DONE', 'REWARDED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- profiles: 1:1 with auth.users(id)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.user_role not null,
  created_at timestamptz not null default now()
);

-- wallets: per-user balances
create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  jelly_normal int not null default 0 check (jelly_normal >= 0),
  jelly_special int not null default 0 check (jelly_special >= 0),
  jelly_bonus int not null default 0 check (jelly_bonus >= 0),
  cash_balance int not null default 0 check (cash_balance >= 0),
  updated_at timestamptz not null default now()
);

-- monthly challenge selection (2 of 3)
create table if not exists public.challenge_months (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  year_month text not null, -- 'YYYY-MM'
  challenge_a public.challenge_type not null,
  challenge_b public.challenge_type not null,
  pair_key text not null,   -- sorted 'A|B'
  created_at timestamptz not null default now(),
  unique (child_id, year_month)
);

create index if not exists idx_challenge_months_child_month on public.challenge_months(child_id, year_month);

-- daily status for calendar
create table if not exists public.challenge_days (
  id uuid primary key default gen_random_uuid(),
  challenge_month_id uuid not null references public.challenge_months(id) on delete cascade,
  day_date date not null,
  status public.day_status not null default 'PENDING',
  memo text,
  created_at timestamptz not null default now(),
  unique (challenge_month_id, day_date)
);

-- parent jelly grants log
create table if not exists public.jelly_grants (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid not null references public.profiles(id) on delete cascade,
  challenge public.challenge_type not null,
  target_date date not null, -- completion date
  jelly public.jelly_type not null,
  amount int not null check (amount > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_jelly_grants_child_date on public.jelly_grants(child_id, target_date);

-- jelly -> cash exchanges
create table if not exists public.jelly_exchanges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  jelly public.jelly_type not null,
  amount int not null check (amount > 0),
  exchanged_cash int not null check (exchanged_cash > 0),
  created_at timestamptz not null default now()
);

-- allowance requests
create table if not exists public.allowance_requests (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  requested_cash int not null check (requested_cash >= 0),
  status public.allowance_status not null default 'REQUESTED',
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create index if not exists idx_allowance_requests_child on public.allowance_requests(child_id, created_at desc);

-- allowance proofs (storage paths)
create table if not exists public.allowance_proofs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.allowance_requests(id) on delete cascade,
  uploader_parent_id uuid not null references public.profiles(id) on delete cascade,
  object_path text not null,
  created_at timestamptz not null default now()
);

-- helper view
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

-- profiles: self select + parents select all
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

-- wallets: self select/update + parents select
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

-- challenge_months: child select + parents select
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

-- challenge_days: child/parent select
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

-- jelly_grants: child select own, parent select/insert
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

-- jelly_exchanges: self select/insert + parent select
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

-- allowance_requests: child select/insert + parent select
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

-- allowance_proofs: child/parent select; parent insert
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
