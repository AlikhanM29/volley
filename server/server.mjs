import http from 'node:http';
import {existsSync,createReadStream,statSync} from 'node:fs';
import {dirname,resolve,sep,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {openDb} from './db.mjs';
import {Platform,digest,fail} from './platform.mjs';
const here=dirname(fileURLToPath(import.meta.url));
export function createApp({dbPath,webRoot=resolve(here,'../build/web')}={}) {
 const db=openDb(dbPath);const platform=new Platform(db);const buckets=new Map();
 const allowed=new Set((process.env.ALLOWED_ORIGINS||'http://localhost:5173,http://127.0.0.1:5173').split(','));
 const cookie=(value,max)=>`volley_session=${value}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${max}${process.env.COOKIE_SECURE==='true'?'; Secure':''}`;
 const server=http.createServer(async(req,res)=>{
  const send=(status,value)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value));};
  res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','same-origin');
  const origin=req.headers.origin,own=process.env.PUBLIC_ORIGIN||`http://${req.headers.host}`;
  if(origin&&origin!==own&&!allowed.has(origin)){send(403,{error:'Origin not allowed'});return;}
  if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Access-Control-Allow-Credentials','true');res.setHeader('Vary','Origin');}
  res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');res.setHeader('Access-Control-Allow-Methods','GET, POST, PATCH, DELETE, OPTIONS');
  if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
  try {
   const url=new URL(req.url,'http://localhost'),path=url.pathname;
   if(path==='/api/health'){send(200,{service:'volley',version:2,ok:true});return;}
   if(!path.startsWith('/api/')){
    if(req.method!=='GET')fail(405,'Әдіс қолжетімсіз.');
    const root=resolve(webRoot),file=resolve(root,'.'+decodeURIComponent(path==='/'?'/index.html':path));
    if(!file.startsWith(root+sep)||!existsSync(file)||!statSync(file).isFile())fail(404,'Бет табылмады.');
    const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.ttf':'font/ttf'};
    res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream'});createReadStream(file).pipe(res);return;
   }
   const short=path.slice(4);let body={};
   if(['POST','PATCH','DELETE'].includes(req.method)){
    if(!req.headers['content-type']?.startsWith('application/json'))fail(415,'JSON қажет.');
    const chunks=[];let bytes=0;
    for await(const c of req){bytes+=c.length;if(bytes>65536)fail(413,'Сұрау тым үлкен.');chunks.push(c);}
    try{body=JSON.parse(Buffer.concat(chunks).toString('utf8')||'{}');}catch{fail(400,'JSON қатесі.');}
    if(!body||typeof body!=='object'||Array.isArray(body))fail(400,'Деректер қате.');
   }
   // Bounded per-IP windows protect both credential hashing and code redemption.
   if(['/register','/login','/admin/redeem','/users/search'].includes(short)){
    const ts=Date.now();for(const [k,v] of buckets)if(v.until<ts)buckets.delete(k);
    const key=req.socket.remoteAddress+':'+short,v=buckets.get(key)||{n:0,until:ts+900000};
    if(++v.n>60)fail(429,'Тым көп әрекет. Кейінірек қайталаңыз.');buckets.set(key,v);
   }
   const token=req.headers.authorization?.replace(/^Bearer /,'')||req.headers.cookie?.split('; ').find(c=>c.startsWith('volley_session='))?.slice(15);
   const user=platform.session(token);
   if(short==='/logout'&&req.method==='POST'){if(token)platform.run('DELETE FROM sessions WHERE hash=?',digest(token));res.setHeader('Set-Cookie',cookie('',0));send(200,{ok:true});return;}
   const result=await platform.route(req.method,short,body,user,url.searchParams);
   if(result.token)res.setHeader('Set-Cookie',cookie(result.token,604800));
   send(req.method==='POST'&&['/register','/teams','/matches','/tournaments','/admin/codes'].includes(short)?201:200,result);
  }catch(e){if(!res.headersSent)send(e.status||500,{error:e.status?e.message:'Сервер қатесі. Қайта көріңіз.'});if(!e.status)console.error('API error:',e.message);}
 });
 server.requestTimeout=15000;return {server,db,platform};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const {server}=createApp();server.listen(Number(process.env.PORT||8080),process.env.HOST||'127.0.0.1',()=>console.log('Volley server v2 ready'));
}
