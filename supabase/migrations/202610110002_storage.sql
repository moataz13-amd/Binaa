insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('operations','operations',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']),
('catalog','catalog',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy operational_upload on storage.objects for insert to authenticated with check(bucket_id='operations' and public.is_staff() and (storage.foldername(name))[1]=auth.uid()::text);
create policy operational_read on storage.objects for select to authenticated using(bucket_id='operations' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.attachments a where a.path=name)));
create policy catalog_read on storage.objects for select to authenticated using(bucket_id='catalog' and public.is_staff());
create policy catalog_upload on storage.objects for insert to authenticated with check(bucket_id='catalog' and public.has_role(array['owner','administrator']));
