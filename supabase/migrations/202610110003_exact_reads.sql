-- PostgREST normally serializes NUMERIC as JSON numbers. Exact string projections
-- prevent JavaScript rounding. security_invoker preserves the source table's RLS.
create view public.custody_transactions_read with (security_invoker=true) as select id,account_id,shift_id,amount::text,kind,operation_id,reversal_of,created_by,created_at from public.custody_transactions;
create view public.expenses_read with (security_invoker=true) as select id,shift_id,truck_id,employee_id,category_id,amount::text,note,transaction_id,created_at from public.expenses;
create view public.customer_invoices_read with (security_invoker=true) as select id,customer_id,delivery_id,amount::text,cost::text,created_at from public.customer_invoices;
create view public.customer_payments_read with (security_invoker=true) as select id,customer_id,shift_id,amount::text,transaction_id,created_at from public.customer_payments;
create view public.cash_transfers_read with (security_invoker=true) as select id,shift_id,sender_id,receiver_id,amount::text,status,created_at from public.cash_transfers;
create view public.reconciliation_records_read with (security_invoker=true) as select id,shift_id,expected::text,counted::text,difference::text,note,submitted_by,approved_by,approved_at,created_at from public.reconciliation_records;
create view public.customer_prices_read with (security_invoker=true) as select id,customer_id,material_id,transaction_type,unit_price::text from public.customer_prices;
create view public.delivery_items_read with (security_invoker=true) as select id,delivery_id,material_id,quantity::text,unit from public.delivery_items;
create view public.material_movements_read with (security_invoker=true) as select id,shift_id,delivery_id,material_id,site_id,quantity::text,kind,ownership,source_id,destination_id,created_by,created_at from public.material_movements;
grant select on public.custody_transactions_read,public.expenses_read,public.customer_invoices_read,public.customer_payments_read,public.cash_transfers_read,public.reconciliation_records_read,public.customer_prices_read,public.delivery_items_read,public.material_movements_read to authenticated;
revoke all on public.custody_transactions_read,public.expenses_read,public.customer_invoices_read,public.customer_payments_read,public.cash_transfers_read,public.reconciliation_records_read,public.customer_prices_read,public.delivery_items_read,public.material_movements_read from anon;
