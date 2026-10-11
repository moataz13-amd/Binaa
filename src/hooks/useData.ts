import {useEffect} from 'react';
import {useQuery,useQueryClient} from '@tanstack/react-query';
import {client} from '../lib/supabase';
import {cache,cached,sync} from '../lib/offline';
import {tables,type Row} from '../lib/types';
const exactTables=new Set(['custody_transactions','expenses','customer_invoices','customer_payments','cash_transfers','reconciliation_records','customer_prices','delivery_items','material_movements']);
export function useData(userId?:string){
 const queryClient=useQueryClient();
 const query=useQuery({queryKey:['operations',userId],enabled:!!userId,queryFn:async()=>{
   if(!navigator.onLine){const previous=await cached(userId!);if(previous)return previous;throw new Error('لا توجد بيانات محفوظة على هذا الجهاز. اتصل بالإنترنت أولًا.');}
   const entries=await Promise.all(tables.map(async table=>{
    const all:Row[]=[];let start=0;
    while(true){const {data,error}=await client().from(exactTables.has(table)?`${table}_read`:table).select('*').order('id').range(start,start+999);if(error)throw error;all.push(...data as Row[]);if(data.length<1000)break;start+=1000;}
    return [table,all] as const;
   }));const snapshot=Object.fromEntries(entries);await cache(userId!,snapshot);return snapshot;
 },retry:1,staleTime:15000,networkMode:'always'});
 useEffect(()=>{if(!userId)return;const refresh=()=>{void sync(userId).then(()=>queryClient.invalidateQueries({queryKey:['operations',userId]}));};window.addEventListener('online',refresh);const c=client().channel(`operations-${userId}`).on('postgres_changes',{event:'*',schema:'public'},()=>void queryClient.invalidateQueries({queryKey:['operations',userId]})).subscribe();void sync(userId);return()=>{window.removeEventListener('online',refresh);void client().removeChannel(c);};},[userId,queryClient]);
 return query;
}
