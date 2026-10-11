import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { VitePWA } from 'vite-plugin-pwa';
export default defineConfig({ plugins: [react(), tailwindcss(), VitePWA({ registerType:'autoUpdate', includeAssets:['icon.svg'], manifest:{name:'بناء لإدارة العمليات',short_name:'بناء',lang:'ar',dir:'rtl',start_url:'/',display:'standalone',background_color:'#F7F9FC',theme_color:'#142B45',icons:[{src:'/icon.svg',sizes:'any',type:'image/svg+xml',purpose:'any'}]},workbox:{skipWaiting:true,clientsClaim:true,navigateFallback:'/index.html',globPatterns:['**/*.{js,css,html,svg,woff2,png}'],runtimeCaching:[]}})], build:{chunkSizeWarningLimit:650,rollupOptions:{output:{manualChunks:{charts:['recharts'],supabase:['@supabase/supabase-js'],forms:['react-hook-form','@hookform/resolvers','zod']}}}} });
