import React from 'react';
import ReactDOM from 'react-dom/client';
import {BrowserRouter} from 'react-router-dom';
import {QueryClient,QueryClientProvider} from '@tanstack/react-query';
import '@fontsource/cairo/arabic-400.css';
import '@fontsource/cairo/arabic-500.css';
import '@fontsource/cairo/arabic-600.css';
import '@fontsource/cairo/arabic-700.css';
import '@fontsource/cairo/arabic-800.css';
import './styles.css';
import App from './App';
const queryClient=new QueryClient({defaultOptions:{queries:{refetchOnWindowFocus:true}}});
class ErrorBoundary extends React.Component<{children:React.ReactNode},{failed:boolean}>{state={failed:false};static getDerivedStateFromError(){return {failed:true};}render(){return this.state.failed?<main className="setup-panel"><h1>حصل خطأ في عرض الصفحة</h1><p>العمليات المحفوظة على الجهاز لم تُحذف. أعد تحميل الصفحة وحاول تاني.</p><button className="btn primary" onClick={()=>window.location.reload()}>إعادة التحميل</button></main>:this.props.children;}}
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><ErrorBoundary><QueryClientProvider client={queryClient}><BrowserRouter><App/></BrowserRouter></QueryClientProvider></ErrorBoundary></React.StrictMode>);
