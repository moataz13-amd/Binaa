import {useEffect} from 'react';
import {useQuery,useQueryClient} from '@tanstack/react-query';
import {client} from '../lib/supabase';
import {cache,cached,sync} from '../lib/offline';
import {tables,type Row} from '../lib/types';
const exactTables=new Set(['custody_transactions','expenses','customer_invoices','customer_payments','cash_transfers','reconciliation_records','customer_prices','delivery_items','material_movements']);
async function loadTable(table:string){
 const all:Row[]=[];let start=0;
 while(true){const {data,error}=await client().from(exactTables.has(table)?`${table}_read`:table).select('*').order('id').range(start,start+999);if(error)throw error;all.push(...data as Row[]);if(data.length<1000)break;start+=1000;}
 return [table,all] as const;
}
async function loadTables(){
 const loaded:Array<readonly[string,Row[]]>=[];
 for(let start=0;start<tables.length;start+=3)loaded.push(...await Promise.all(tables.slice(start,start+3).map(loadTable)));
 return Object.fromEntries(loaded);
}
export function useData(userId?:string){
 const queryClient=useQueryClient();
 const query=useQuery({queryKey:['operations',userId],enabled:!!userId,queryFn:async()=>{
   if(!navigator.onLine){const previous=await cached(userId!);if(previous)return previous;throw new Error('لا توجد بيانات محفوظة على هذا الجهاز. اتصل بالإنترنت أولًا.');}
   const snapshot=await loadTables();await cache(userId!,snapshot);return snapshot;
 },retry:1,staleTime:30000,networkMode:'always'});
 useEffect(()=>{
  if(!userId)return;
  let refreshTimer:number|undefined;
  const refresh=()=>{window.clearTimeout(refreshTimer);refreshTimer=window.setTimeout(()=>void queryClient.invalidateQueries({queryKey:['operations',userId]}),500);};
  const triggerSync=()=>{void sync(userId).then(refresh);};
  window.addEventListener('online',triggerSync);
  const onVisibilityChange=()=>{if(document.visibilityState==='visible')triggerSync();};
  document.addEventListener('visibilitychange',onVisibilityChange);
  const interval=setInterval(triggerSync,60000);

  const c=client().channel(`operations-${userId}`).on('postgres_changes',{event:'*',schema:'public'},()=>{
   refresh();
  }).subscribe();
  triggerSync();
  return()=>{
   window.removeEventListener('online',triggerSync);
   document.removeEventListener('visibilitychange',onVisibilityChange);
   clearInterval(interval);
   window.clearTimeout(refreshTimer);
   void client().removeChannel(c);
  };
 },[userId,queryClient]);
 return query;
}
