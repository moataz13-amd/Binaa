// Integer cents across all UI arithmetic. SQL read views return exact decimal strings.
export function cents(input:unknown):bigint {
 const s=String(input??'0'); if(!/^-?\d+(\.\d{1,2})?$/.test(s)) throw new Error('INVALID_MONEY');
 const negative=s.startsWith('-'); const [whole,fraction='']=s.replace('-','').split('.');
 const n=BigInt(whole)*100n+BigInt(fraction.padEnd(2,'0')); return negative?-n:n;
}
export function decimal(value:bigint):string {const n=value<0n?-value:value; return `${value<0n?'-':''}${n/100n}.${String(n%100n).padStart(2,'0')}`;}
export function money(input:unknown):string {const n=typeof input==='bigint'?input:cents(input);const raw=decimal(n);const [a,b]=raw.split('.');return a.replace(/\B(?=(\d{3})+(?!\d))/g,',')+(b==='00'?'':'.'+b);}
export function sum(values:unknown[]):bigint {return values.reduce<bigint>((a,b)=>a+cents(b),0n);}
export function normalizeDigits(s:string):string {return s.replace(/[٠-٩]/g,d=>String(d.charCodeAt(0)-1632)).replace(/[۰-۹]/g,d=>String(d.charCodeAt(0)-1776)).replace(/٫/g,'.');}
export function reconciliation(expected:unknown,counted:unknown){return {difference:decimal(cents(counted)-cents(expected)),requiresApproval:true};}
