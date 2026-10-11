import { createClient } from 'npm:@supabase/supabase-js@2';
// JWT is verified explicitly to support publishable keys and asymmetric signing.
Deno.serve(async (request: Request) => {
 const origin = Deno.env.get('APP_ORIGIN') ?? '';
 const cors = {'Access-Control-Allow-Origin': origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
 if(request.method==='OPTIONS') return new Response(null,{headers:cors});
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
 if(request.method!=='POST') return reply({error:'METHOD_NOT_ALLOWED'},405);
 if(request.headers.get('origin') && request.headers.get('origin')!==origin) return reply({error:'ORIGIN_NOT_ALLOWED'},403);
 if(Number(request.headers.get('content-length')??0)>32768) return reply({error:'PAYLOAD_TOO_LARGE'},413);
 const authorization=request.headers.get('authorization');
 if(!authorization?.startsWith('Bearer ')) return reply({error:'UNAUTHORIZED'},401);
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
 const {data:{user},error:authError}=await client.auth.getUser(authorization.slice(7));
 if(authError || !user) return reply({error:'UNAUTHORIZED'},401);
 try {
   const raw=await request.text(); if(raw.length>32768) return reply({error:'PAYLOAD_TOO_LARGE'},413);
   const body=JSON.parse(raw);
   if(typeof body.operation_id!=='string'||typeof body.operation_kind!=='string'||!body.payload||Array.isArray(body.payload)) return reply({error:'INVALID_REQUEST'},400);
   const {data,error}=await client.rpc('perform_operation',body);
   if(error) return reply({error:error.message,code:error.code},error.message.includes('FORBIDDEN')?403:409);
   return reply(data);
 } catch { return reply({error:'INVALID_REQUEST'},400); }
});
