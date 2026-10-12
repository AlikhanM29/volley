import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {DatabaseSync} from 'node:sqlite';
import {createApp} from './server.mjs';
import {openDb} from './db.mjs';

async function setup(t){
 const dir=mkdtempSync(join(tmpdir(),'volley-v2-')),dbPath=join(dir,'test.sqlite');
 const app=createApp({dbPath});app.server.listen(0,'127.0.0.1');await once(app.server,'listening');
 t.after(async()=>{await new Promise(r=>app.server.close(r));app.db.close();rmSync(dir,{recursive:true,force:true});});
 const call=async(method,path,body,token)=>{
  const res=await fetch(`http://127.0.0.1:${app.server.address().port}/api${path}`,{method,
   headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
   ...(body?{body:JSON.stringify(body)}:{})});
  return {status:res.status,body:await res.json(),cookie:res.headers.get('set-cookie')};
 };
 let count=0;
 const register=async(role='user',extra={})=>{const r=await call('POST','/register',{name:'Тест '+(++count),email:'test'+count+'@example.test',password:'Password123',role,...extra});assert.equal(r.status,201,JSON.stringify(r.body));return r.body;};
 const bootstrap=app.platform.issueCode(null,{},true).code;
 const admin=await register('user',{admin_code:bootstrap});
 return {...app,call,register,admin,dbPath};
}
test('registration rejects privilege escalation, login/logout and coach onboarding',async t=>{
 const {call,register,admin}=await setup(t);
 assert.equal((await call('POST','/register',{name:'x',email:'x@x.test',password:'Password123',role:'admin'})).status,400);
 assert.equal((await call('POST','/register',{name:'x',email:'x@x.test',password:'Password123',role:'organizer'})).status,400);
 const coach=await register('coach');
 assert.equal((await call('GET','/me',null,coach.token)).body.team,null);
 assert.equal((await call('GET','/users/search?q=te',null,coach.token)).status,403);
 assert.equal((await call('POST','/login',{email:coach.user.email,password:'bad'})).status,401);
 const login=await call('POST','/login',{email:coach.user.email,password:'Password123'});
 assert.equal(login.status,200);assert.match(login.cookie,/HttpOnly/);assert.equal(login.body.user.hash,undefined);
 await call('POST','/logout',{},login.body.token);
 assert.equal((await call('GET','/me',null,login.body.token)).body.user,null);
 assert.equal((await call('PATCH','/admin/users/'+admin.user.id,{active:0},admin.token)).status,409);
});
test('invitations require consent, deduplicate, private inbox, captain and own-team permissions',async t=>{
 const {call,register}=await setup(t);const coach=await register('coach'),other=await register('coach'),player=await register('user',{phone:'+7 777 123 45 67'}),decline=await register();
 const r=await call('POST','/teams',{name:'Қыран',city:'Астана',description:'Команда'},coach.token);
 assert.equal(r.status,201);const team=r.body.team.id;
 assert.equal((await call('POST','/teams',{name:'X',city:'Y',description:'Test team'},player.token)).status,403);
 assert.equal((await call('POST','/teams',{name:'X',city:'Y',description:'Test team'},coach.token)).status,409);
 for(const q of [player.user.name,player.user.email,player.user.phone,player.user.id]){
  const search=await call('GET','/users/search?q='+encodeURIComponent(q),null,coach.token);
  assert(search.body.users.some(u=>u.id===player.user.id));
 }
 assert.equal((await call('POST','/teams/'+team+'/invitations',{user_id:player.user.id},other.token)).status,403);
 assert.equal((await call('POST','/teams/'+team+'/invitations',{user_id:'missing'},coach.token)).status,404);
 assert.equal((await call('POST','/teams/'+team+'/invitations',{user_id:player.user.id},coach.token)).status,200);
 assert.equal((await call('GET','/teams/'+team)).body.team.members.length,0);
 assert.equal((await call('POST','/teams/'+team+'/invitations',{user_id:player.user.id},coach.token)).status,409);
 const inv=(await call('GET','/invitations',null,player.token)).body.invitations[0];
 assert.equal((await call('GET','/notifications',null,player.token)).body.notifications.length,1);
 assert.equal((await call('PATCH','/invitations/'+inv.id,{status:'accepted'},decline.token)).status,404);
 assert.equal((await call('PATCH','/invitations/'+inv.id,{status:'accepted'},player.token)).status,200);
 assert.equal((await call('PATCH','/invitations/'+inv.id,{status:'accepted'},player.token)).status,409);
 assert.equal((await call('GET','/teams/'+team)).body.team.members.length,1);
 await call('PATCH','/teams/'+team+'/members/'+player.user.id,{captain:1},coach.token);
 assert.equal((await call('GET','/teams/'+team)).body.team.members[0].captain,1);
 await call('POST','/teams/'+team+'/invitations',{user_id:decline.user.id},coach.token);
 const second=(await call('GET','/invitations',null,decline.token)).body.invitations[0];
 await call('PATCH','/invitations/'+second.id,{status:'rejected'},decline.token);
 assert.equal((await call('GET','/teams/'+team)).body.team.members.length,1);
 await call('DELETE','/teams/'+team+'/members/'+player.user.id,{},coach.token);
 assert.equal((await call('GET','/teams/'+team)).body.team.members.length,0);
});
test('admin codes are hashed, expire, revoke, limited use, transactional and audited',async t=>{
 const {call,register,admin,db,platform}=await setup(t);const ordinary=await register();
 assert.equal((await call('POST','/admin/codes',{},ordinary.token)).status,403);
 let issued=(await call('POST','/admin/codes',{max_uses:1,hours:2},admin.token)).body;
 const stored=db.prepare('SELECT * FROM admin_codes WHERE id=?').get(issued.id);
 assert.notEqual(stored.hash,issued.code);assert.equal(stored.code,undefined);
 const first=await register('user',{admin_code:issued.code});assert.equal(first.user.role,'admin');
 assert.equal((await call('POST','/admin/redeem',{code:issued.code},ordinary.token)).status,400);
 issued=(await call('POST','/admin/codes',{max_uses:2,hours:1},admin.token)).body;
 db.prepare('UPDATE admin_codes SET expires=0 WHERE id=?').run(issued.id);
 assert.equal((await call('POST','/admin/redeem',{code:issued.code},ordinary.token)).status,400);
 issued=(await call('POST','/admin/codes',{max_uses:2,hours:1},admin.token)).body;
 await call('DELETE','/admin/codes/'+issued.id,{},admin.token);
 assert.equal((await call('POST','/admin/redeem',{code:issued.code},ordinary.token)).status,400);
 issued=(await call('POST','/admin/codes',{max_uses:1,hours:1},admin.token)).body;
 const second=await register();
 const attempts=await Promise.all([ordinary,second].map(u=>call('POST','/admin/redeem',{code:issued.code},u.token)));
 assert.deepEqual(attempts.map(r=>r.status).sort(),[200,400]);
 const events=(await call('GET','/admin/audit',null,admin.token)).body.events;
 assert(events.some(e=>e.action==='admin.grant'));assert(events.some(e=>e.action==='admin_code.revoke'));
 assert(!JSON.stringify(events).includes(issued.code));
 assert.throws(()=>platform.issueCode(null,{},true));
});
test('match creation validates roles, active teams and schedule conflicts including updates',async t=>{
 const {call,register,admin}=await setup(t);const user=await register();
 const teams=[];for(let i=0;i<3;i++)teams.push((await call('POST','/teams',{name:'Team '+i,city:'City',description:'Test team'},admin.token)).body.team.id);
 const b={team_a:teams[0],team_b:teams[1],start_at:'2026-12-01T10:00:00Z',location:'Hall',format:'indoor',best_of:5};
 assert.equal((await call('POST','/matches',b,user.token)).status,403);
 assert.equal((await call('POST','/matches',{...b,team_b:teams[0]},admin.token)).status,400);
 const m=await call('POST','/matches',b,admin.token);assert.equal(m.status,201);
 assert.equal((await call('POST','/matches',{...b,team_b:teams[2]},admin.token)).status,409);
 const later=await call('POST','/matches',{...b,start_at:'2026-12-01T11:00:00Z'},admin.token);
 assert.equal((await call('PATCH','/matches/'+later.body.match.id,{start_at:b.start_at},admin.token)).status,409);
 await call('PATCH','/teams/'+teams[2],{active:0},admin.token);
 assert.equal((await call('POST','/matches',{...b,team_b:teams[2]},admin.token)).status,400);
 assert.equal((await call('POST','/matches/'+m.body.match.id+'/result',{score_a:2,score_b:2},admin.token)).status,400);
 await call('DELETE','/matches/'+m.body.match.id,{},admin.token);
 assert.equal((await call('POST','/matches',b,admin.token)).status,201);
});
test('round robin pair uniqueness, standings, playoff byes and all winners advance (2–9 teams)',async t=>{
 const {call,admin}=await setup(t);
 const teams=[];for(let i=0;i<9;i++)teams.push((await call('POST','/teams',{name:'Team '+i,city:'City',description:'Test team'},admin.token)).body.team.id);
 const base={title:'Cup',start_at:'2027-01-01T10:00:00Z',location:'Hall',format:'indoor',best_of:3,round_minutes:1440};
 const rr=await call('POST','/tournaments',{...base,kind:'round_robin',team_ids:teams.slice(0,5)},admin.token);
 let tournament=(await call('POST','/tournaments/'+rr.body.tournament.id+'/generate',{},admin.token)).body.tournament;
 assert.equal(tournament.matches.length,10);
 assert.equal(new Set(tournament.matches.map(m=>[m.team_a,m.team_b].sort().join())).size,10);
 assert.equal((await call('POST','/tournaments/'+rr.body.tournament.id+'/generate',{},admin.token)).status,409);
 for(const m of tournament.matches)assert.equal((await call('POST','/matches/'+m.id+'/result',{score_a:2,score_b:0},admin.token)).status,200);
 tournament=(await call('GET','/tournaments/'+tournament.id)).body.tournament;
 assert.equal(tournament.standings.reduce((s,r)=>s+r.played,0),20);
 for(let n=2;n<=9;n++){
  const created=await call('POST','/tournaments',{...base,start_at:`2027-${String(n).padStart(2,'0')}-01T10:00:00Z`,kind:'playoff',team_ids:teams.slice(0,n)},admin.token);
  assert.equal(created.status,201);
  const tid=created.body.tournament.id;
  let generated=await call('POST','/tournaments/'+tid+'/generate',{},admin.token);assert.equal(generated.status,200,JSON.stringify(generated.body));
  let played=0;let finished=false;
  while(!finished){
   const current=(await call('GET','/tournaments/'+tid)).body.tournament;
   const ready=current.matches.filter(m=>m.team_a&&m.team_b&&!m.winner_id);
   for(const m of ready){const r=await call('POST','/matches/'+m.id+'/result',{score_a:2,score_b:0},admin.token);assert.equal(r.status,200,JSON.stringify(r.body));played++;}
   finished=ready.length===0;
  }
  const final=(await call('GET','/tournaments/'+tid)).body.tournament;
  assert(final.matches.at(-1).winner_id);assert.equal(played,n-1);
 }
});
test('legacy migration preserves accounts and archived tournaments and is idempotent',()=>{
 const dir=mkdtempSync(join(tmpdir(),'volley-migration-')),path=join(dir,'old.sqlite');let db=new DatabaseSync(path);
 try{
  db.exec("CREATE TABLE users(id TEXT PRIMARY KEY,name TEXT,email TEXT UNIQUE,role TEXT,salt TEXT,hash TEXT); CREATE TABLE tournaments(id TEXT PRIMARY KEY,owner_id TEXT,data TEXT);");
  db.prepare('INSERT INTO users VALUES(?,?,?,?,?,?)').run('1','Owner','owner@example.test','organizer','salt','hash');
  db.prepare('INSERT INTO tournaments VALUES(?,?,?)').run('1','1','{"title":"Old Cup"}');db.close();
  db=openDb(path);assert.equal(db.prepare('SELECT role FROM users').get().role,'user');
  assert.equal(db.prepare('SELECT count(*) AS n FROM legacy_tournaments').get().n,1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM tournaments').get().n,0);db.close();
  db=openDb(path);assert.equal(db.prepare('SELECT count(*) AS n FROM schema_migrations').get().n,1);
  assert(readdirSync(dir).some(n=>n.includes('pre-v2')));
 }finally{db.close();rmSync(dir,{recursive:true,force:true});}
});

test('generation rolls back on conflict and future playoff participants reserve their slot',async t=>{
 const {call,admin}=await setup(t);const ids=[];
 for(let i=0;i<4;i++)ids.push((await call('POST','/teams',{name:'Conflict '+i,city:'City',description:'Team'},admin.token)).body.team.id);
 const base={start_at:'2028-01-01T10:00:00Z',location:'Hall',format:'indoor',best_of:5};
 assert.equal((await call('POST','/matches',{...base,start_at:'2028-02-30T10:00:00Z',team_a:ids[0],team_b:ids[1]},admin.token)).status,400);
 const standalone=(await call('POST','/matches',{...base,team_a:ids[1],team_b:ids[2]},admin.token)).body.match;
 const tournament=(await call('POST','/tournaments',{...base,title:'Rollback',kind:'round_robin',round_minutes:1440,team_ids:ids},admin.token)).body.tournament;
 assert.equal((await call('POST','/tournaments/'+tournament.id+'/generate',{},admin.token)).status,409);
 const rolled=(await call('GET','/tournaments/'+tournament.id)).body.tournament;
 assert.equal(rolled.generated,0);assert.equal(rolled.matches.length,0);
 await call('DELETE','/matches/'+standalone.id,{},admin.token);
 const playoff=(await call('POST','/tournaments',{...base,title:'Playoff',kind:'playoff',round_minutes:1440,team_ids:ids},admin.token)).body.tournament;
 const generated=(await call('POST','/tournaments/'+playoff.id+'/generate',{},admin.token)).body.tournament;
 const final=generated.matches.at(-1);
 assert.equal((await call('POST','/matches',{...base,start_at:final.start_at,team_a:ids[0],team_b:ids[2]},admin.token)).status,409);
 const opening=generated.matches[0];
 assert.equal((await call('PATCH','/matches/'+opening.id,{location:'Another hall'},admin.token)).status,200);
 for(const m of generated.matches.filter(m=>m.round===1))await call('POST','/matches/'+m.id+'/result',{score_a:3,score_b:1},admin.token);
 await call('POST','/matches/'+final.id+'/result',{score_a:3,score_b:1},admin.token);
 assert.equal((await call('DELETE','/matches/'+opening.id,{},admin.token)).status,409);
 assert.equal((await call('POST','/matches/'+opening.id+'/result',{score_a:0,score_b:3},admin.token)).status,409);
});

test('blocking, team removal and role boundaries cannot be bypassed from API',async t=>{
 const {call,register,admin}=await setup(t);const coach=await register('coach'),player=await register();
 const team=(await call('POST','/teams',{name:'Private team',city:'City',description:'Team'},coach.token)).body.team;
 assert.equal((await call('GET','/users/search?q=te',null,player.token)).status,403);
 assert.equal((await call('GET','/invitations')).status,401);
 assert.equal((await call('POST','/tournaments',{},coach.token)).status,403);
 assert.equal((await call('POST','/matches',{},coach.token)).status,403);
 assert.equal((await call('PATCH','/admin/users/'+player.user.id,{role:'admin'},admin.token)).status,400);
 await call('POST','/teams/'+team.id+'/invitations',{user_id:player.user.id},coach.token);
 await call('DELETE','/teams/'+team.id,{},admin.token);
 const invitation=(await call('GET','/invitations',null,player.token)).body.invitations[0];
 assert.equal(invitation.status,'cancelled');
 assert.equal((await call('PATCH','/invitations/'+invitation.id,{status:'accepted'},player.token)).status,409);
 await call('PATCH','/admin/users/'+player.user.id,{active:0},admin.token);
 assert.equal((await call('GET','/me',null,player.token)).body.user,null);
 assert.equal((await call('POST','/login',{email:player.user.email,password:'Password123'})).status,401);
});
