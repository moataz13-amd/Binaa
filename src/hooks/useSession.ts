import {useState,useEffect} from 'react';
import type {Session} from '@supabase/supabase-js';
import {supabase} from '../lib/supabase';
export function useSession(){const [session,setSession]=useState<Session|null>(null);const [loading,setLoading]=useState(!!supabase);useEffect(()=>{if(!supabase)return;void supabase.auth.getSession().then(({data})=>{setSession(data.session);setLoading(false);});const {data}=supabase.auth.onAuthStateChange((_e,s)=>{setSession(s);setLoading(false);});return()=>data.subscription.unsubscribe();},[]);return {session,loading};}
