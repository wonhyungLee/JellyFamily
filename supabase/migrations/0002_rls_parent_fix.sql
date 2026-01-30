-- Fix infinite recursion in RLS by using a SECURITY DEFINER helper
create or replace function public.is_parent(user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = user_id
      and p.role = 'PARENT'
  );
$$;

revoke all on function public.is_parent(uuid) from public;
grant execute on function public.is_parent(uuid) to authenticated;

-- profiles: parent select all
drop policy if exists "profiles: parent select all" on public.profiles;
create policy "profiles: parent select all"
on public.profiles for select
to authenticated
using (public.is_parent(auth.uid()));

-- wallets: parent select
drop policy if exists "wallets: parent select" on public.wallets;
create policy "wallets: parent select"
on public.wallets for select
to authenticated
using (public.is_parent(auth.uid()));

-- challenge_months: parent select
drop policy if exists "challenge_months: parent select all" on public.challenge_months;
create policy "challenge_months: parent select all"
on public.challenge_months for select
to authenticated
using (public.is_parent(auth.uid()));

-- challenge_days: parent select
drop policy if exists "challenge_days: parent select" on public.challenge_days;
create policy "challenge_days: parent select"
on public.challenge_days for select
to authenticated
using (public.is_parent(auth.uid()));

-- jelly_grants: parent select/insert
drop policy if exists "jelly_grants: parent select" on public.jelly_grants;
create policy "jelly_grants: parent select"
on public.jelly_grants for select
to authenticated
using (public.is_parent(auth.uid()));

drop policy if exists "jelly_grants: parent insert" on public.jelly_grants;
create policy "jelly_grants: parent insert"
on public.jelly_grants for insert
to authenticated
with check (public.is_parent(auth.uid()));

-- jelly_exchanges: parent select
drop policy if exists "jelly_exchanges: parent select" on public.jelly_exchanges;
create policy "jelly_exchanges: parent select"
on public.jelly_exchanges for select
to authenticated
using (public.is_parent(auth.uid()));

-- allowance_requests: parent select
drop policy if exists "allowance_requests: parent select" on public.allowance_requests;
create policy "allowance_requests: parent select"
on public.allowance_requests for select
to authenticated
using (public.is_parent(auth.uid()));

-- allowance_proofs: parent select/insert
drop policy if exists "allowance_proofs: parent select" on public.allowance_proofs;
create policy "allowance_proofs: parent select"
on public.allowance_proofs for select
to authenticated
using (public.is_parent(auth.uid()));

drop policy if exists "allowance_proofs: parent insert" on public.allowance_proofs;
create policy "allowance_proofs: parent insert"
on public.allowance_proofs for insert
to authenticated
with check (public.is_parent(auth.uid()));
