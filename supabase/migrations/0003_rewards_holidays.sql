-- public holidays (date list)
create table if not exists public.public_holidays (
  day_date date primary key,
  name text
);

-- reward claims for special/bonus
create table if not exists public.reward_claims (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles(id) on delete cascade,
  reward_type public.jelly_type not null,
  period_key text not null,
  created_at timestamptz not null default now(),
  check (reward_type in ('SPECIAL', 'BONUS')),
  unique (child_id, reward_type, period_key)
);

create index if not exists idx_reward_claims_child on public.reward_claims(child_id, created_at desc);

alter table public.public_holidays enable row level security;
alter table public.reward_claims enable row level security;

-- public_holidays: anyone authenticated can read
create policy "public_holidays: select all"
on public.public_holidays for select
to authenticated
using (true);

-- reward_claims: child read own, parent read all
create policy "reward_claims: child select own"
on public.reward_claims for select
to authenticated
using (child_id = auth.uid());

create policy "reward_claims: parent select"
on public.reward_claims for select
to authenticated
using (public.is_parent(auth.uid()));
