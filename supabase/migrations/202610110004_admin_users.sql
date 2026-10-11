create or replace function public.manage_user_role(target_user uuid, target_role text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); actor_owner boolean; actor_admin boolean;
begin
 if actor is null then raise exception 'FORBIDDEN'; end if;
 actor_owner:=public.has_role(array['owner']); actor_admin:=public.has_role(array['administrator']);
 if not (actor_owner or actor_admin) or target_user=actor then raise exception 'FORBIDDEN'; end if;
 if target_role not in ('owner','administrator','accountant','driver','worker') then raise exception 'INVALID_ROLE'; end if;
 if actor_admin and target_role not in ('driver','worker') then raise exception 'FORBIDDEN'; end if;
 if actor_admin and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=target_user and r.name in ('owner','administrator','accountant')) then raise exception 'FORBIDDEN'; end if;
 if not exists(select 1 from public.profiles where id=target_user) then raise exception 'USER_NOT_FOUND'; end if;
 delete from public.user_roles where user_id=target_user;
 insert into public.user_roles(user_id,role_id) select target_user,id from public.roles where name=target_role;
 insert into public.employees(profile_id,name) select id,name from public.profiles where id=target_user on conflict(profile_id) do update set active=true,name=excluded.name;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(actor,'manage_user_role',target_user,jsonb_build_object('role',target_role));
 return jsonb_build_object('status','updated','user_id',target_user,'role',target_role);
end $$;
revoke execute on function public.manage_user_role(uuid,text) from public,anon;
grant execute on function public.manage_user_role(uuid,text) to authenticated;
