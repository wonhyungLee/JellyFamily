-- Allow parents to upload allowance proof images to storage
-- storage.objects has RLS enabled by default

drop policy if exists "storage: parents upload allowance proofs" on storage.objects;

create policy "storage: parents upload allowance proofs"
on storage.objects for insert
 to authenticated
with check (
  bucket_id = 'allowance-proofs'
  and owner = auth.uid()
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'PARENT'
  )
);
