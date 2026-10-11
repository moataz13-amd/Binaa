import {openDB} from 'idb';
import {client} from './supabase';
import type {Snapshot} from './types';
export type Pending={id:string;userId:string;kind:string;payload:Record<string,unknown>;state:'pending'|'conflict'|'error';error?:string;createdAt:string};
const db=()=>openDB('binaa-private-v1',1,{upgrade(d){d.createObjectStore('queue',{keyPath:'id'});d.createObjectStore('snapshots');}});
const emit=()=>window.dispatchEvent(new Event('queue-change'));
export async function pending(userId:string):Promise<Pending[]>{return (await(await db()).getAll('queue')).filter((x:Pending)=>x.userId===userId);}
export async function cached(userId:string):Promise<Snapshot|undefined>{return(await db()).get('snapshots',userId);}
export async function cache(userId:string,data:Snapshot){await(await db()).put('snapshots',data,userId);}
export async function clearPrivateCache(userId:string){await(await db()).delete('snapshots',userId);}
export async function submit(userId:string,kind:string,payload:Record<string,unknown>,id=crypto.randomUUID()){
 const op:Pending={id,userId,kind,payload,state:'pending',createdAt:new Date().toISOString()};
 await(await db()).put('queue',op);emit();
 if(!navigator.onLine)return {pending:true,id};
 await send(op);return {pending:false,id};
}
async function send(op:Pending){
 const {data:{session}}=await client().auth.getSession();if(session?.user.id!==op.userId)throw new Error('UNAUTHORIZED');
 // RPC enforces the same transaction boundary as the optional Edge Function gateway.
 const {error}=await client().rpc('perform_operation',{operation_id:op.id,operation_kind:op.kind,payload:op.payload});
 if(error){
   const transport=!navigator.onLine||/fetch|network|timeout/i.test(error.message);
   op.state=transport?'pending':/CONFLICT|LOCKED/.test(error.message)?'conflict':'error';op.error=error.message;
   await(await db()).put('queue',op);emit();throw new Error(error.message);
 }
 await(await db()).delete('queue',op.id);emit();
}
let syncing=false;
export async function sync(userId:string){if(syncing||!navigator.onLine)return;syncing=true;try{for(const op of await pending(userId)){if(op.state!=='pending')continue;try{await send(op);}catch{break;}}}finally{syncing=false;}}
export async function retry(id:string,userId:string){const op=(await pending(userId)).find(p=>p.id===id);if(!op)return;await send(op);}
// Never change a queued payload automatically: the user must review a fresh operation.
export async function discard(id:string,userId:string){const op=(await pending(userId)).find(p=>p.id===id);if(op?.state==='pending')throw new Error('يجب التحقق من الخادم قبل حذف عملية قد تكون وصلت.');if(op)await(await db()).delete('queue',id);emit();}
