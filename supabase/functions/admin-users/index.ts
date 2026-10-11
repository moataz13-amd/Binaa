import {createClient} from 'npm:@supabase/supabase-js@2';
const defaultOrigin='https://binaa-construction-operations.bronzesugar5.chatgpt.site';
const allowedOrigins=(Deno.env.get('APP_ORIGINS')??defaultOrigin).split(',').map(x=>x.trim());
Deno.serve(async(request:Request)=>{
 const origin=request.headers.get('origin')??defaultOrigin;const allowed=allowedOrigins.includes(origin);
 const cors={'Access-Control-Allow-Origin':allowed?origin:defaultOrigin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
 if(request.method==='OPTIONS')return new Response(null,{headers:cors});
 if(request.method!=='POST'||!allowed)return reply({error:'FORBIDDEN'},403);
 const authorization=request.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return reply({error:'UNAUTHORIZED'},401);
 const url=Deno.env.get('SUPABASE_URL')!;const anon=Deno.env.get('SUPABASE_ANON_KEY')!;const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const userClient=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
 const {data:{user},error:authError}=await userClient.auth.getUser(authorization.slice(7));if(authError||!user)return reply({error:'UNAUTHORIZED'},401);
 const [{data:isOwner},{data:isAdmin}]=await Promise.all([userClient.rpc('has_role',{wanted:['owner']}),userClient.rpc('has_role',{wanted:['administrator']})]);if(!isOwner&&!isAdmin)return reply({error:'FORBIDDEN'},403);
 try{
  const body=await request.json();const name=String(body.name??'').trim();const phone=String(body.phone??'').replace(/[^0-9+]/g,'');const email=String(body.email??'').toLowerCase();const password=String(body.password??'');const role=String(body.role??'');
  if(name.length<2||name.length>100||!/^\+?20?1[0125]\d{8}$/.test(phone)||!/^201[0125]\d{8}@binaa\.invalid$/.test(email)||password.length<8)return reply({error:'INVALID_REQUEST'},400);
  if(!['driver','worker'].includes(role)&&!(isOwner&&['administrator','accountant'].includes(role)))return reply({error:'FORBIDDEN'},403);
  const admin=createClient(url,service,{auth:{persistSession:false}});const {data:created,error:createError}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{name,phone}});if(createError)return reply({error:createError.message},createError.message.toLowerCase().includes('already')?409:400);
  try{const uid=created.user.id;const {error:p}=await admin.from('profiles').upsert({id:uid,name});if(p)throw p;const {error:e}=await admin.from('employees').upsert({profile_id:uid,name,active:true},{onConflict:'profile_id'});if(e)throw e;const {data:r,error:re}=await admin.from('roles').select('id').eq('name',role).single();if(re)throw re;const {error:ur}=await admin.from('user_roles').insert({user_id:uid,role_id:r.id});if(ur)throw ur;await admin.from('audit_logs').insert({actor_id:user.id,action:'create_user',entity_id:uid,detail:{role,phone}});return reply({status:'created',user_id:uid});}catch(error){await admin.auth.admin.deleteUser(created.user.id);throw error;}
 }catch(error){return reply({error:error instanceof Error?error.message:'INVALID_REQUEST'},400);}
});
