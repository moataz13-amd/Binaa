export interface VoiceProvider {speak(text:string,prompt?:string):Promise<void>;stop():void;}
export type VoiceSettings={muted:boolean;volume:number;rate:number;recordings:Record<string,string>};
const defaults:VoiceSettings={muted:false,volume:1,rate:0.85,recordings:{}};
export function voiceSettings():VoiceSettings{try{return {...defaults,...JSON.parse(localStorage.getItem('binaa-voice')||'{}')};}catch{return defaults;}}
export function saveVoiceSettings(s:VoiceSettings){localStorage.setItem('binaa-voice',JSON.stringify(s));}
let audio:HTMLAudioElement|undefined;
export const voice:VoiceProvider={
 stop(){window.speechSynthesis?.cancel();audio?.pause();},
 async speak(text,prompt){
  const settings=voiceSettings(); if(settings.muted)throw new Error('الصوت مكتوم. يمكنك قراءة الملخص أو تشغيل الصوت.');
  this.stop();
  const recording=prompt&&settings.recordings[prompt];
  if(recording){audio=new Audio(recording);audio.volume=settings.volume;audio.playbackRate=settings.rate;await audio.play();return;}
  if(!('speechSynthesis' in window))throw new Error('الصوت غير متاح على الجهاز. استخدم الملخص المرئي.');
  const voices=window.speechSynthesis.getVoices();
  const selected=voices.find(v=>v.lang.toLowerCase()==='ar-eg')??voices.find(v=>v.lang.startsWith('ar'));
  if(!selected)throw new Error('لا يوجد صوت عربي على الجهاز. أضف صوتًا عربيًا أو تسجيلًا من الإعدادات.');
  await new Promise<void>((resolve,reject)=>{const u=new SpeechSynthesisUtterance(text);u.voice=selected;u.lang=selected.lang;u.volume=settings.volume;u.rate=settings.rate;u.onend=()=>resolve();u.onerror=()=>reject(new Error('تعذّر تشغيل الصوت. يمكنك التأكيد من الملخص المرئي.'));window.speechSynthesis.speak(u);});
 }
};
type Recognition={lang:string;continuous:boolean;interimResults:boolean;onresult:((e:{results:{[n:number]:{[n:number]:{transcript:string}}}})=>void)|null;onerror:((e:{error:string})=>void)|null;start():void;stop():void};
declare global {interface Window{SpeechRecognition?:new()=>Recognition;webkitSpeechRecognition?:new()=>Recognition;}}
export function dictate(onText:(text:string)=>void,onError:(message:string)=>void){const C=window.SpeechRecognition??window.webkitSpeechRecognition;if(!C){onError('الإدخال الصوتي غير متاح. استخدم الاختيارات أو لوحة الأرقام.');return;}const r=new C();r.lang='ar-EG';r.continuous=false;r.interimResults=false;r.onresult=e=>onText(e.results[0][0].transcript);r.onerror=()=>onError('لم نسمع بوضوح. جرّب مرة أخرى أو أدخل يدويًا.');r.start();return ()=>r.stop();}
