import {createClient} from '@supabase/supabase-js';
export const supabaseUrl=import.meta.env.VITE_SUPABASE_URL;
export const supabaseKey=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const url=supabaseUrl;
const key=supabaseKey;
export const configured=Boolean(url&&key);
export const supabase=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export function client(){if(!supabase)throw new Error('SUPABASE_NOT_CONFIGURED');return supabase;}

export async function invokeAdminUsers(body:Record<string,unknown>){
 const {data:{session},error}=await client().auth.getSession();
 if(error||!session)throw new Error('UNAUTHORIZED');
 let lastError:unknown;
 for(let attempt=0;attempt<2;attempt++){
  const controller=new AbortController();const timeout=window.setTimeout(()=>controller.abort(),15000);
  try{
   const response=await fetch(`${supabaseUrl}/functions/v1/admin-users`,{method:'POST',signal:controller.signal,headers:{Authorization:`Bearer ${session.access_token}`,apikey:supabaseKey,'Content-Type':'application/json','x-client-info':'binaa-web'},body:JSON.stringify(body)});
   const result=await response.json().catch(()=>({error:`HTTP_${response.status}`}));
   if(!response.ok)throw new Error(String(result?.error??`HTTP_${response.status}`));
   return result;
  }catch(e){lastError=e;if(e instanceof Error&&!/fetch|network|abort/i.test(e.message))throw e;if(attempt===0)await new Promise(resolve=>window.setTimeout(resolve,700));}
  finally{window.clearTimeout(timeout);}
 }
 throw new Error(lastError instanceof Error?lastError.message:'EDGE_FUNCTION_UNREACHABLE');
}
