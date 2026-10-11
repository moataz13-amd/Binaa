-- Store custody handover parties when adding custody to an existing shift.
create or replace function public.perform_operation(operation_id uuid, operation_kind text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); s public.shifts; op private.operations; v_result jsonb; eid uuid:=gen_random_uuid();
 sid uuid; acc uuid; other_acc uuid; tx uuid; amount numeric(16,2); qty numeric(14,3); bal numeric(16,2); reserved numeric(16,2);
 cust uuid; site uuid; mat uuid; unit_name text; recipient uuid; transfer public.cash_transfers; rec public.reconciliation_records; opening_expense jsonb; opening_expense_amount numeric(16,2); opening_total numeric(16,2):=0;
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
   select id into acc from public.custody_accounts where user_id=driver for update;
   amount:=coalesce(nullif(payload->>'initial_custody','')::numeric,0);
   if amount<0 then raise exception 'INVALID_AMOUNT'; end if;
   if amount>0 then
     if length(trim(coalesce(payload->>'cash_from','')))<2 or length(trim(coalesce(payload->>'cash_to','')))<2 then raise exception 'CASH_PARTIES_REQUIRED'; end if;
     insert into public.custody_transactions(account_id,shift_id,amount,kind,operation_id,created_by,cash_from,cash_to)
       values(acc,eid,amount,'issue',operation_id,actor,trim(payload->>'cash_from'),trim(payload->>'cash_to'));
   end if;
   if jsonb_typeof(payload->'expenses')='array' then
     for opening_expense in select value from jsonb_array_elements(payload->'expenses') loop
       opening_expense_amount:=(opening_expense->>'amount')::numeric;
       if opening_expense_amount is null or opening_expense_amount<=0 then raise exception 'INVALID_AMOUNT'; end if;
       if length(trim(coalesce(opening_expense->>'note','')))<1 then raise exception 'EXPENSE_NOTE_REQUIRED'; end if;
       if not exists(select 1 from public.expense_categories where id=(opening_expense->>'category_id')::uuid and active) then raise exception 'CATEGORY_INACTIVE'; end if;
       opening_total:=opening_total+opening_expense_amount;
       if opening_total>amount then raise exception 'INSUFFICIENT_CUSTODY'; end if;
       tx:=gen_random_uuid();
       insert into public.custody_transactions(id,account_id,shift_id,amount,kind,operation_id,created_by)
         values(tx,acc,eid,-opening_expense_amount,'expense',operation_id,actor);
       insert into public.expenses(shift_id,truck_id,employee_id,category_id,amount,note,transaction_id)
         values(eid,truck,driver,(opening_expense->>'category_id')::uuid,opening_expense_amount,trim(opening_expense->>'note'),tx);
     end loop;
   end if;
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
       if operation_kind='issue' then
         if length(trim(coalesce(payload->>'cash_from','')))<2 or length(trim(coalesce(payload->>'cash_to','')))<2 then raise exception 'CASH_PARTIES_REQUIRED'; end if;
         insert into public.custody_transactions(id,account_id,shift_id,amount,kind,operation_id,created_by,cash_from,cash_to)
           values(eid,acc,sid,amount,operation_kind,operation_id,actor,trim(payload->>'cash_from'),trim(payload->>'cash_to'));
       else
         insert into public.custody_transactions(id,account_id,shift_id,amount,kind,operation_id,created_by)
           values(eid,acc,sid,-amount,operation_kind,operation_id,actor);
       end if;
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

