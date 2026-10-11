-- One private contractor per Supabase project. Money is EGP NUMERIC, never float.
create schema if not exists private;
revoke all on schema private from public;
create table public.roles (id uuid primary key default gen_random_uuid(), name text unique not null check(name in ('owner','administrator','accountant','driver','worker')));
insert into public.roles(name) values ('owner'),('administrator'),('accountant'),('driver'),('worker');
create table public.profiles (id uuid primary key references auth.users(id), name text not null, photo_path text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.user_roles (id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id), role_id uuid not null references public.roles(id), unique(user_id,role_id));
create table public.employees (id uuid primary key default gen_random_uuid(), profile_id uuid unique not null references public.profiles(id), name text not null, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.trucks (id uuid primary key default gen_random_uuid(), name text not null, registration text unique not null, photo_path text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.materials (id uuid primary key default gen_random_uuid(), name text not null, unit text not null check(unit in ('m3','ton','kg','bag','load')), photo_path text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.customers (id uuid primary key default gen_random_uuid(), name text not null, phone text, photo_path text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.construction_sites (id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id), name text not null, location text, photo_path text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.expense_categories (id uuid primary key default gen_random_uuid(), name text not null unique, icon text not null default 'Receipt', active boolean not null default true, created_at timestamptz not null default now());
insert into public.expense_categories(name,icon) values ('وقود','Fuel'),('صيانة','Wrench'),('عمالة','Users'),('تحميل وتنزيل','PackageOpen'),('طريق','Route'),('مصروف آخر','Receipt');
create table public.shifts (id uuid primary key default gen_random_uuid(), reference bigint generated always as identity unique, truck_id uuid not null references public.trucks(id), driver_id uuid not null references public.profiles(id), status text not null default 'active' check(status in ('open','active','pending_reconciliation','closed','reopened')), started_at timestamptz not null default now(), ended_at timestamptz, version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create unique index one_active_truck on public.shifts(truck_id) where status <> 'closed';
create unique index one_active_driver on public.shifts(driver_id) where status <> 'closed';
create table public.shift_assignments (id uuid primary key default gen_random_uuid(), shift_id uuid not null references public.shifts(id), user_id uuid not null references public.profiles(id), unique(shift_id,user_id));
create table public.deliveries (id uuid primary key default gen_random_uuid(), shift_id uuid not null references public.shifts(id), truck_id uuid not null references public.trucks(id), customer_id uuid not null references public.customers(id), site_id uuid not null references public.construction_sites(id), transaction_type text not null check(transaction_type in ('sale','transport','sale_transport')), status text not null default 'delivered' check(status in ('delivered','reversed')), receipt_name text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now());
create table public.delivery_items (id uuid primary key default gen_random_uuid(), delivery_id uuid not null references public.deliveries(id), material_id uuid not null references public.materials(id), quantity numeric(14,3) not null check(quantity>0), unit text not null);
create table public.inventory_locations (id uuid primary key default gen_random_uuid(), name text not null, active boolean not null default true);
create table public.material_movements (id uuid primary key default gen_random_uuid(), shift_id uuid not null references public.shifts(id), delivery_id uuid references public.deliveries(id), material_id uuid not null references public.materials(id), site_id uuid not null references public.construction_sites(id), quantity numeric(14,3) not null check(quantity>0), kind text not null check(kind in ('delivery','unloading')), ownership text not null default 'customer' check(ownership in ('customer','contractor','third_party')), source_id uuid references public.inventory_locations(id), destination_id uuid references public.inventory_locations(id), created_by uuid not null references public.profiles(id), created_at timestamptz not null default now());
create table public.custody_accounts (id uuid primary key default gen_random_uuid(), user_id uuid not null unique references public.profiles(id), created_at timestamptz not null default now());
create table public.custody_transactions (id uuid primary key default gen_random_uuid(), account_id uuid not null references public.custody_accounts(id), shift_id uuid references public.shifts(id), amount numeric(16,2) not null check(amount<>0), kind text not null check(kind in ('issue','payment','expense','transfer_in','transfer_out','return','reversal')), operation_id uuid not null, reversal_of uuid unique references public.custody_transactions(id), created_by uuid not null references public.profiles(id), created_at timestamptz not null default now());
create table public.expenses (id uuid primary key default gen_random_uuid(), shift_id uuid not null references public.shifts(id), truck_id uuid not null references public.trucks(id), employee_id uuid not null references public.profiles(id), category_id uuid not null references public.expense_categories(id), amount numeric(16,2) not null check(amount>0), note text, transaction_id uuid not null unique references public.custody_transactions(id), created_at timestamptz not null default now());
create table public.customer_invoices (id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id), delivery_id uuid not null unique references public.deliveries(id), amount numeric(16,2) not null check(amount>=0), cost numeric(16,2) check(cost>=0), created_at timestamptz not null default now());
create table public.customer_payments (id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id), shift_id uuid not null references public.shifts(id), amount numeric(16,2) not null check(amount>0), transaction_id uuid not null unique references public.custody_transactions(id), created_at timestamptz not null default now());
create table public.payment_allocations (id uuid primary key default gen_random_uuid(), payment_id uuid not null references public.customer_payments(id), invoice_id uuid not null references public.customer_invoices(id), amount numeric(16,2) not null check(amount>0), unique(payment_id,invoice_id));
create table public.cash_transfers (id uuid primary key default gen_random_uuid(), shift_id uuid not null references public.shifts(id), sender_id uuid not null references public.profiles(id), receiver_id uuid not null references public.profiles(id), amount numeric(16,2) not null check(amount>0), status text not null default 'pending' check(status in ('pending','accepted','cancelled')), created_at timestamptz not null default now(), check(sender_id<>receiver_id));
create table public.reconciliation_records (id uuid primary key default gen_random_uuid(), shift_id uuid not null references public.shifts(id), expected numeric(16,2) not null, counted numeric(16,2) not null check(counted>=0), difference numeric(16,2) generated always as (counted-expected) stored, note text, submitted_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id), approved_at timestamptz, created_at timestamptz not null default now());
create table public.attachments (id uuid primary key default gen_random_uuid(), shift_id uuid references public.shifts(id), entity_id uuid, path text unique not null, owner_id uuid not null references public.profiles(id) default auth.uid(), content_type text not null check(content_type in ('image/jpeg','image/png','image/webp','application/pdf')), created_at timestamptz not null default now());
create table public.audit_logs (id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id), action text not null, entity_id uuid, detail jsonb not null default '{}', created_at timestamptz not null default now());
create table public.system_settings (id uuid primary key default gen_random_uuid(), key text unique not null, value jsonb not null, updated_at timestamptz not null default now());
insert into public.system_settings(key,value) values ('business','{"name":"بناء","currency":"EGP","timezone":"Africa/Cairo","inventory_enabled":false}');
create table public.customer_prices (id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id), material_id uuid not null references public.materials(id), transaction_type text not null check(transaction_type in ('sale','transport','sale_transport')), unit_price numeric(16,2) not null check(unit_price>=0), unique(customer_id,material_id,transaction_type));
create table private.operations (id uuid primary key, actor_id uuid not null, kind text not null, payload jsonb not null, result jsonb, created_at timestamptz not null default now());

create function public.has_role(wanted text[]) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=auth.uid() and r.name=any(wanted)) $$;
create function public.is_staff() returns boolean language sql stable security definer set search_path='' as $$ select public.has_role(array['owner','administrator','accountant','driver','worker']) $$;
create function public.can_shift(sid uuid) returns boolean language sql stable security definer set search_path='' as $$ select public.has_role(array['owner','administrator','accountant']) or exists(select 1 from public.shifts s where s.id=sid and s.driver_id=auth.uid()) or exists(select 1 from public.shift_assignments a where a.shift_id=sid and a.user_id=auth.uid()) $$;
create function private.immutable() returns trigger language plpgsql set search_path='' as $$ begin raise exception 'IMMUTABLE_RECORD'; end $$;
create function private.touch() returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
do $$ declare t text; begin
 foreach t in array array['custody_transactions','expenses','customer_payments','customer_invoices','payment_allocations','material_movements','deliveries','delivery_items','audit_logs'] loop
 execute format('create trigger immutable before update or delete on public.%I for each row execute function private.immutable()',t);
 end loop;
 foreach t in array array['profiles','employees','trucks','materials','customers','construction_sites','shifts','system_settings'] loop
 execute format('create trigger touch before update on public.%I for each row execute function private.touch()',t);
 end loop;
end $$;
-- Authenticated grants are intentionally read-only for transactional tables.
do $$ declare t text; begin
 foreach t in array array['roles','profiles','user_roles','employees','trucks','materials','customers','construction_sites','expense_categories','shifts','shift_assignments','deliveries','delivery_items','inventory_locations','material_movements','custody_accounts','custody_transactions','expenses','customer_invoices','customer_payments','payment_allocations','cash_transfers','reconciliation_records','attachments','audit_logs','system_settings','customer_prices'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['roles','trucks','materials','customers','construction_sites','expense_categories','inventory_locations','system_settings'] loop
 execute format('create policy staff_read on public.%I for select to authenticated using (public.is_staff())',t);
 end loop;
 foreach t in array array['trucks','materials','customers','construction_sites','expense_categories','inventory_locations','customer_prices','system_settings'] loop
 execute format('grant insert, update on public.%I to authenticated',t);
 execute format('create policy manager_insert on public.%I for insert to authenticated with check(public.has_role(array[''owner'',''administrator'']))',t);
 execute format('create policy manager_update on public.%I for update to authenticated using(public.has_role(array[''owner'',''administrator''])) with check(public.has_role(array[''owner'',''administrator'']))',t);
 end loop;
 foreach t in array array['deliveries','material_movements','shift_assignments','reconciliation_records'] loop
 execute format('create policy assigned_read on public.%I for select to authenticated using(public.can_shift(shift_id))',t);
 end loop;
end $$;
create policy staff_profiles on public.profiles for select to authenticated using(public.is_staff());
create policy own_roles on public.user_roles for select to authenticated using(user_id=auth.uid() or public.has_role(array['owner','administrator']));
create policy staff_employees on public.employees for select to authenticated using(public.is_staff());
create policy assigned_shifts on public.shifts for select to authenticated using(public.can_shift(id));
create policy assigned_items on public.delivery_items for select to authenticated using(exists(select 1 from public.deliveries d where d.id=delivery_id and public.can_shift(d.shift_id)));
create policy own_accounts on public.custody_accounts for select to authenticated using(user_id=auth.uid() or public.has_role(array['owner','administrator','accountant']));
create policy own_transactions on public.custody_transactions for select to authenticated using(exists(select 1 from public.custody_accounts a where a.id=account_id and (a.user_id=auth.uid() or public.has_role(array['owner','administrator','accountant']))));
create policy expense_read on public.expenses for select to authenticated using(employee_id=auth.uid() or public.has_role(array['owner','administrator','accountant']));
create policy invoice_read on public.customer_invoices for select to authenticated using(public.has_role(array['owner','administrator','accountant']) or exists(select 1 from public.deliveries d join public.shifts s on s.id=d.shift_id where d.id=delivery_id and s.driver_id=auth.uid()));
create policy payment_read on public.customer_payments for select to authenticated using(public.has_role(array['owner','administrator','accountant']) or exists(select 1 from public.shifts s where s.id=shift_id and s.driver_id=auth.uid()));
create policy allocation_read on public.payment_allocations for select to authenticated using(public.has_role(array['owner','administrator','accountant']));
create policy price_read on public.customer_prices for select to authenticated using(public.has_role(array['owner','administrator','accountant','driver']));
create policy transfer_read on public.cash_transfers for select to authenticated using(sender_id=auth.uid() or receiver_id=auth.uid() or public.has_role(array['owner','administrator','accountant']));
create policy audit_read on public.audit_logs for select to authenticated using(public.has_role(array['owner','accountant']));
create policy attachment_read on public.attachments for select to authenticated using(owner_id=auth.uid() or (shift_id is not null and public.can_shift(shift_id)) or public.has_role(array['owner','administrator','accountant']));
grant insert on public.attachments to authenticated;
create policy attachment_insert on public.attachments for insert to authenticated with check(public.is_staff() and owner_id=auth.uid() and split_part(path,'/',1)=auth.uid()::text and (shift_id is null or public.can_shift(shift_id)));

create index shifts_driver on public.shifts(driver_id);
create index assignments_user on public.shift_assignments(user_id);
create index delivery_shift on public.deliveries(shift_id,created_at);
create index delivery_customer on public.deliveries(customer_id);
create index items_delivery on public.delivery_items(delivery_id);
create index movements_shift on public.material_movements(shift_id);
create index expenses_shift on public.expenses(shift_id,created_at);
create index ledger_account on public.custody_transactions(account_id,created_at);
create index ledger_shift on public.custody_transactions(shift_id);
create index invoices_customer on public.customer_invoices(customer_id);
create index payments_customer on public.customer_payments(customer_id);
create index sites_customer on public.construction_sites(customer_id);
create index reconciliation_shift on public.reconciliation_records(shift_id);

-- All writes below are atomic, authenticated, idempotent and audited.
create function public.perform_operation(operation_id uuid, operation_kind text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); s public.shifts; op private.operations; v_result jsonb; eid uuid:=gen_random_uuid();
 sid uuid; acc uuid; other_acc uuid; tx uuid; amount numeric(16,2); qty numeric(14,3); bal numeric(16,2); reserved numeric(16,2);
 cust uuid; site uuid; mat uuid; unit_name text; recipient uuid; transfer public.cash_transfers; rec public.reconciliation_records;
 manager boolean; finance boolean; truck uuid; driver uuid; rname text; target uuid; price numeric(16,2);
begin
 if actor is null or not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 manager:=public.has_role(array['owner','administrator']); finance:=public.has_role(array['owner','accountant']);
 -- Advisory lock serializes retries for the same request before checking the receipt.
 perform pg_advisory_xact_lock(hashtextextended(operation_id::text,0));
 select * into op from private.operations where id=operation_id;
 if found then
   if op.actor_id<>actor or op.kind<>operation_kind or op.payload<>payload then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
   return op.result;
 end if;
 insert into private.operations(id,actor_id,kind,payload) values(operation_id,actor,operation_kind,payload);
 if operation_kind='open_shift' then
   if not(manager or public.has_role(array['driver'])) then raise exception 'FORBIDDEN'; end if;
   driver:=coalesce(nullif(payload->>'driver_id','')::uuid,actor); truck:=(payload->>'truck_id')::uuid;
   if driver<>actor and not manager then raise exception 'FORBIDDEN'; end if;
   if not exists(select 1 from public.employees e where e.profile_id=driver and e.active) then raise exception 'EMPLOYEE_INACTIVE'; end if;
   if not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=driver and r.name='driver') then raise exception 'DRIVER_REQUIRED'; end if;
   if not exists(select 1 from public.trucks where id=truck and active) then raise exception 'TRUCK_INACTIVE'; end if;
   insert into public.shifts(id,truck_id,driver_id) values(eid,truck,driver);
   insert into public.custody_accounts(user_id) values(driver) on conflict(user_id) do nothing;
   if jsonb_typeof(payload->'worker_ids')='array' then
     if not manager then raise exception 'FORBIDDEN'; end if;
     insert into public.shift_assignments(shift_id,user_id) select eid,value::uuid from jsonb_array_elements_text(payload->'worker_ids');
   end if;
 elsif operation_kind='set_role' then
   if not public.has_role(array['owner']) then raise exception 'FORBIDDEN'; end if;
   target:=(payload->>'user_id')::uuid; rname:=payload->>'role';
   if target=actor then raise exception 'SELF_ROLE_CHANGE_DENIED'; end if;
   if not exists(select 1 from public.roles where name=rname) then raise exception 'INVALID_ROLE'; end if;
   delete from public.user_roles where user_id=target;
   insert into public.user_roles(user_id,role_id) select target,id from public.roles where name=rname;
   insert into public.employees(profile_id,name) select id,name from public.profiles where id=target on conflict(profile_id) do nothing;
 elsif operation_kind='reverse_cash' then
   if not finance then raise exception 'FORBIDDEN'; end if;
   select t.shift_id into sid from public.custody_transactions t where t.id=(payload->>'transaction_id')::uuid and t.kind in ('issue','return');
   if sid is null then raise exception 'REVERSAL_REQUIRES_ISSUE_OR_RETURN'; end if;
   select * into s from public.shifts where id=sid for update;
   if s.status not in ('active','open','reopened') then raise exception 'SHIFT_LOCKED'; end if;
   if length(trim(coalesce(payload->>'note','')))<3 then raise exception 'REASON_REQUIRED'; end if;
   select account_id into acc from public.custody_transactions where id=(payload->>'transaction_id')::uuid;
   perform 1 from public.custody_accounts where id=acc for update;
   insert into public.custody_transactions(id,account_id,shift_id,amount,kind,operation_id,reversal_of,created_by)
     select eid,account_id,shift_id,-amount,'reversal',operation_id,id,actor from public.custody_transactions where id=(payload->>'transaction_id')::uuid;
   update public.shifts set version=version+1 where id=sid;
 elsif operation_kind='accept_transfer' then
   select * into transfer from public.cash_transfers where id=(payload->>'transfer_id')::uuid;
   if not found or transfer.receiver_id<>actor then raise exception 'FORBIDDEN'; end if;
   select * into s from public.shifts where id=transfer.shift_id for update;
   select * into transfer from public.cash_transfers where id=transfer.id for update;
   if transfer.status<>'pending' then raise exception 'TRANSFER_ALREADY_RESOLVED'; end if;
   if s.status not in ('active','open','reopened') then raise exception 'SHIFT_LOCKED'; end if;
   insert into public.custody_accounts(user_id) values(actor) on conflict(user_id) do nothing;
   select id into acc from public.custody_accounts where user_id=transfer.sender_id;
   select id into other_acc from public.custody_accounts where user_id=actor;
   perform 1 from public.custody_accounts where id in (acc,other_acc) order by id for update;
   select coalesce(sum(t.amount),0) into bal from public.custody_transactions t where t.account_id=acc;
   if bal<transfer.amount then raise exception 'INSUFFICIENT_CUSTODY'; end if;
   insert into public.custody_transactions(account_id,shift_id,amount,kind,operation_id,created_by) values
     (acc,s.id,-transfer.amount,'transfer_out',operation_id,actor),(other_acc,s.id,transfer.amount,'transfer_in',operation_id,actor);
   update public.cash_transfers set status='accepted' where id=transfer.id;
   update public.shifts set version=version+1 where id=s.id;
 else
   sid:=(payload->>'shift_id')::uuid;
   select * into s from public.shifts where id=sid for update;
   if not found or not public.can_shift(sid) then raise exception 'FORBIDDEN'; end if;
   if coalesce((payload->>'version')::integer,-1)<>s.version then raise exception 'SHIFT_CONFLICT'; end if;
   if operation_kind='approve_close' then
     if not finance or s.status<>'pending_reconciliation' then raise exception 'FORBIDDEN'; end if;
     select * into rec from public.reconciliation_records where shift_id=sid order by created_at desc limit 1 for update;
     if rec.difference<>0 and length(trim(coalesce(payload->>'note','')))<3 then raise exception 'REASON_REQUIRED'; end if;
     update public.reconciliation_records set approved_by=actor, approved_at=now(),note=payload->>'note' where id=rec.id;
     update public.shifts set status='closed',ended_at=now() where id=sid;
   elsif operation_kind='reopen_shift' then
     if not public.has_role(array['owner']) or s.status<>'closed' then raise exception 'FORBIDDEN'; end if;
     if length(trim(coalesce(payload->>'note','')))<3 then raise exception 'REASON_REQUIRED'; end if;
     update public.shifts set status='reopened',ended_at=null where id=sid;
   else
     if s.status not in ('active','open','reopened') then raise exception 'SHIFT_LOCKED'; end if;
     if operation_kind<>'unloading' and not (manager or finance or (s.driver_id=actor and public.has_role(array['driver']))) then raise exception 'FORBIDDEN'; end if;
     if operation_kind='unloading' and not(manager or public.has_role(array['driver','worker'])) then raise exception 'FORBIDDEN'; end if;
     select id into acc from public.custody_accounts where user_id=s.driver_id for update;
     select coalesce(sum(t.amount),0) into bal from public.custody_transactions t where account_id=acc;
     select coalesce(sum(t.amount),0) into reserved from public.cash_transfers t where sender_id=s.driver_id and status='pending';
     if operation_kind in ('expense','payment','issue','return','transfer') then
       amount:=(payload->>'amount')::numeric;
       if amount is null or amount<=0 or (payload->>'amount')::numeric<>amount then raise exception 'INVALID_AMOUNT'; end if;
     end if;
     if operation_kind='assign_worker' then
       if not manager then raise exception 'FORBIDDEN'; end if;
       target:=(payload->>'user_id')::uuid;
       if not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id join public.employees e on e.profile_id=ur.user_id where ur.user_id=target and r.name='worker' and e.active) then raise exception 'WORKER_REQUIRED'; end if;
       insert into public.shift_assignments(shift_id,user_id) values(sid,target) on conflict(shift_id,user_id) do nothing;
     elsif operation_kind in ('delivery','unloading') then
       cust:=(payload->>'customer_id')::uuid; site:=(payload->>'site_id')::uuid; mat:=(payload->>'material_id')::uuid; qty:=(payload->>'quantity')::numeric;
       if qty is null or qty<=0 or qty<>(payload->>'quantity')::numeric then raise exception 'INVALID_QUANTITY'; end if;
       if not exists(select 1 from public.construction_sites where id=site and customer_id=cust and active) then raise exception 'SITE_CUSTOMER_MISMATCH'; end if;
       if not exists(select 1 from public.customers where id=cust and active) then raise exception 'CUSTOMER_INACTIVE'; end if;
       select unit into unit_name from public.materials where id=mat and active;
       if not found then raise exception 'MATERIAL_INACTIVE'; end if;
       if operation_kind='delivery' then
         if payload->>'transaction_type' is null or payload->>'transaction_type' not in ('sale','transport','sale_transport') then raise exception 'INVALID_TYPE'; end if;
         select unit_price into price from public.customer_prices where customer_id=cust and material_id=mat and transaction_type=payload->>'transaction_type';
         if manager or finance then price:=coalesce(nullif(payload->>'unit_price','')::numeric,price); end if;
         if price is null or price<0 then raise exception 'PRICE_REQUIRED'; end if;
         insert into public.deliveries(id,shift_id,truck_id,customer_id,site_id,transaction_type,receipt_name,created_by) values(eid,sid,s.truck_id,cust,site,payload->>'transaction_type',payload->>'receipt_name',actor);
         insert into public.delivery_items(delivery_id,material_id,quantity,unit) values(eid,mat,qty,unit_name);
         insert into public.customer_invoices(customer_id,delivery_id,amount,cost) values(cust,eid,round(qty*price,2),case when manager or finance then nullif(payload->>'cost','')::numeric else null end);
       end if;
       insert into public.material_movements(shift_id,delivery_id,material_id,site_id,quantity,kind,ownership,created_by) values(sid,case when operation_kind='delivery' then eid else null end,mat,site,qty,operation_kind,coalesce(payload->>'ownership','customer'),actor);
     elsif operation_kind='expense' then
       if bal-reserved<amount then raise exception 'INSUFFICIENT_CUSTODY'; end if;
       if not exists(select 1 from public.expense_categories where id=(payload->>'category_id')::uuid and active) then raise exception 'CATEGORY_INACTIVE'; end if;
       insert into public.custody_transactions(account_id,shift_id,amount,kind,operation_id,created_by) values(acc,sid,-amount,'expense',operation_id,actor) returning id into tx;
       insert into public.expenses(id,shift_id,truck_id,employee_id,category_id,amount,note,transaction_id) values(eid,sid,s.truck_id,s.driver_id,(payload->>'category_id')::uuid,amount,payload->>'note',tx);
     elsif operation_kind='payment' then
       cust:=(payload->>'customer_id')::uuid;
       if not exists(select 1 from public.customers where id=cust and active) then raise exception 'CUSTOMER_INACTIVE'; end if;
       insert into public.custody_transactions(account_id,shift_id,amount,kind,operation_id,created_by) values(acc,sid,amount,'payment',operation_id,actor) returning id into tx;
       insert into public.customer_payments(id,customer_id,shift_id,amount,transaction_id) values(eid,cust,sid,amount,tx);
     elsif operation_kind in ('issue','return') then
       if operation_kind='issue' and not (manager or finance) then raise exception 'FORBIDDEN'; end if;
       if operation_kind='return' and not finance then raise exception 'USE_CONFIRMED_TRANSFER'; end if;
       if operation_kind='return' and bal-reserved<amount then raise exception 'INSUFFICIENT_CUSTODY'; end if;
       insert into public.custody_transactions(id,account_id,shift_id,amount,kind,operation_id,created_by) values(eid,acc,sid,case when operation_kind='return' then -amount else amount end,operation_kind,operation_id,actor);
     elsif operation_kind='transfer' then
       if actor<>s.driver_id then raise exception 'SENDER_MUST_CONFIRM'; end if;
       recipient:=(payload->>'receiver_id')::uuid;
       if not exists(select 1 from public.employees where profile_id=recipient and active) then raise exception 'EMPLOYEE_INACTIVE'; end if;
       if bal-reserved<amount then raise exception 'INSUFFICIENT_CUSTODY'; end if;
       insert into public.cash_transfers(id,shift_id,sender_id,receiver_id,amount) values(eid,sid,actor,recipient,amount);
     elsif operation_kind='cancel_transfer' then
       update public.cash_transfers set status='cancelled' where id=(payload->>'transfer_id')::uuid and shift_id=sid and status='pending' and sender_id=actor;
       if not found then raise exception 'FORBIDDEN'; end if;
     elsif operation_kind='close_shift' then
       if exists(select 1 from public.cash_transfers where shift_id=sid and status='pending') then raise exception 'PENDING_TRANSFER'; end if;
       amount:=(payload->>'counted')::numeric;
       if amount is null or amount<0 or amount<>(payload->>'counted')::numeric then raise exception 'INVALID_AMOUNT'; end if;
       -- Count all custody held by this employee, including carry-over from prior shifts.
       insert into public.reconciliation_records(id,shift_id,expected,counted,submitted_by) values(eid,sid,bal,amount,actor);
       update public.shifts set status='pending_reconciliation' where id=sid;
     else raise exception 'UNKNOWN_OPERATION'; end if;
   end if;
   update public.shifts set version=version+1 where id=sid;
 end if;
 v_result:=jsonb_build_object('id',eid,'operation_id',operation_id,'status','confirmed');
 update private.operations set result=v_result where id=operation_id;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(actor,operation_kind,eid,jsonb_build_object('operation_id',operation_id,'shift_id',sid,'note',payload->>'note'));
 return v_result;
end $$;

-- Provisioning creates a profile without privileges. Owner is bootstrapped out of band.
create function private.on_user_created() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.profiles(id,name) values(new.id,coalesce(new.raw_user_meta_data->>'name','مستخدم جديد')); return new;
end $$;
create trigger user_created after insert on auth.users for each row execute function private.on_user_created();
revoke execute on function public.has_role(text[]),public.is_staff(),public.can_shift(uuid),public.perform_operation(uuid,text,jsonb) from public,anon;
grant execute on function public.has_role(text[]),public.is_staff(),public.can_shift(uuid),public.perform_operation(uuid,text,jsonb) to authenticated;
-- Realtime is optional on local test Postgres.
do $$ begin if exists(select 1 from pg_publication where pubname='supabase_realtime') then
 alter publication supabase_realtime add table public.shifts,public.deliveries,public.expenses,public.custody_transactions,public.cash_transfers;
end if; end $$;
