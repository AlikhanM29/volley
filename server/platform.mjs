import {randomUUID,randomBytes,createHash,scrypt as rawScrypt,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {transaction} from './db.mjs';
const scrypt=promisify(rawScrypt);
export const digest=v=>createHash('sha256').update(v).digest('hex');
export const fail=(status,message)=>{throw Object.assign(new Error(message),{status});};
const now=()=>new Date().toISOString();
const id=()=>randomUUID();
const str=(v,label,max=120)=>{if(typeof v!=='string'||!v.trim()||v.trim().length>max)fail(400,`${label}: дұрыс мән енгізіңіз.`);return v.trim();};
const optional=(v,max=1000)=>{if(v==null)return '';if(typeof v!=='string'||v.length>max)fail(400,'Мәтін тым ұзын.');return v.trim();};
const integer=(v,min,max)=>{if(!Number.isInteger(v)||v<min||v>max)fail(400,'Сан шектен тыс.');return v;};
const date=v=>{
 if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(v)||!Number.isFinite(Date.parse(v)))fail(400,'Күн мен уақытты көрсетіңіз.');
 const [y,m,d]=v.slice(0,10).split('-').map(Number);
 if(y<2000||y>2100||m<1||m>12||d<1||d>new Date(Date.UTC(y,m,0)).getUTCDate()||Number(v.slice(11,13))>23||Number(v.slice(14,16))>59)fail(400,'Күн мен уақыт қате.');
 const parsed=new Date(v);parsed.setUTCSeconds(0,0);return parsed.toISOString();
};
const phone=v=>{const s=optional(v,30).replace(/[\s()+-]/g,'');if(s&&!/^\d{7,15}$/.test(s))fail(400,'Телефон нөмірі қате.');return s;};
export const safeUser=u=>u?Object.fromEntries(['id','name','email','role','phone','active'].map(k=>[k,u[k]])):null;

export class Platform {
 constructor(db){this.db=db;}
 one(sql,...p){return this.db.prepare(sql).get(...p);}
 all(sql,...p){return this.db.prepare(sql).all(...p);}
 run(sql,...p){return this.db.prepare(sql).run(...p);}
 tx(fn){return transaction(this.db,fn);}
 audit(actor,action,target,details={}){this.run('INSERT INTO audit_log(actor_id,action,target_id,details,created_at) VALUES(?,?,?,?,?)',actor,action,target,JSON.stringify(details),now());}
 require(u,roles){if(!u||!u.active)fail(401,'Алдымен жүйеге кіріңіз.');if(roles&&!roles.includes(u.role))fail(403,'Бұл әрекетке рұқсат жоқ.');return u;}
 team(teamId){const t=this.one('SELECT * FROM teams WHERE id=? AND deleted=0',teamId);if(!t)fail(404,'Команда табылмады.');return t;}
 manage(u,teamId){this.require(u,['coach','admin']);const t=this.team(teamId);if(u.role!=='admin'&&t.coach_id!==u.id)fail(403,'Тек өз командаңызды басқара аласыз.');return t;}
 activeTeams(ids){if(!Array.isArray(ids)||ids.length<2||ids.length>32||ids.some(v=>typeof v!=='string')||new Set(ids).size!==ids.length)fail(400,'2–32 түрлі команда таңдаңыз.');return ids.map(v=>{const t=this.team(v);if(!t.active)fail(400,'Команда белсенді емес.');return t;});}
 session(token){return token?this.one('SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.hash=? AND s.expires>? AND u.active=1',digest(token),Date.now()):null;}
 newSession(u){const token=randomBytes(32).toString('hex');this.run('DELETE FROM sessions WHERE expires<=?',Date.now());this.run('INSERT INTO sessions VALUES(?,?,?)',digest(token),u.id,Date.now()+7*86400000);return {token,user:safeUser(u)};}
 code(raw){if(typeof raw!=='string'||raw.length>200)fail(400,'Шақыру коды қате.');const c=this.one('SELECT * FROM admin_codes WHERE hash=?',digest(raw.trim()));if(!c||c.revoked||c.expires<=Date.now()||c.uses>=c.max_uses)fail(400,'Код жарамсыз, мерзімі өткен немесе қолданылған.');return c;}
 redeem(u,raw){this.require(u);return this.tx(()=>{if(u.role==='admin')fail(409,'Сіз әкімшісіз.');if(this.one('SELECT 1 FROM teams WHERE coach_id=? AND deleted=0',u.id))fail(409,'Алдымен команданы басқа жаттықтырушыға тапсырыңыз.');const c=this.code(raw);this.run('UPDATE admin_codes SET uses=uses+1 WHERE id=?',c.id);this.run("UPDATE users SET role='admin' WHERE id=?",u.id);this.audit(u.id,'admin.grant',u.id,{codeId:c.id});return {user:safeUser(this.one('SELECT * FROM users WHERE id=?',u.id))};});}
 issueCode(u,b,bootstrap=false){if(!bootstrap)this.require(u,['admin']);return this.tx(()=>{
  if(bootstrap&&(this.one("SELECT 1 FROM users WHERE role='admin'")||this.one('SELECT 1 FROM admin_codes WHERE revoked=0 AND uses<max_uses AND expires>?',Date.now())))fail(409,'Бастапқы код бар немесе әкімші тіркелген.');
  const max=bootstrap?1:integer(b.max_uses??1,1,20),hours=bootstrap?24:integer(b.hours??24,1,168);
  const raw=randomBytes(32).toString('base64url'),codeId=id(),expires=Date.now()+hours*3600000;
  this.run('INSERT INTO admin_codes(id,hash,created_by,expires,max_uses,created_at) VALUES(?,?,?,?,?,?)',codeId,digest(raw),u?.id??null,expires,max,now());
  this.audit(u?.id??null,bootstrap?'admin_code.bootstrap':'admin_code.create',codeId,{max_uses:max,expires});return {code:raw,id:codeId,expires,max_uses:max};
 });}
 async register(b){
  const name=str(b.name,'Аты-жөні',80),email=str(b.email,'Пошта',254).toLowerCase(),tel=phone(b.phone);
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))fail(400,'Пошта мекенжайы қате.');
  if(!['user','coach'].includes(b.role))fail(400,'Пайдаланушы немесе жаттықтырушы рөлін таңдаңыз.');
  if(typeof b.password!=='string'||b.password.length<8||b.password.length>128)fail(400,'Құпиясөз 8–128 таңба болуы керек.');
  const salt=randomBytes(16).toString('hex'),hash=(await scrypt(b.password,salt,64)).toString('hex');
  return this.tx(()=>{
   if(this.one('SELECT 1 FROM users WHERE email=?',email))fail(409,'Бұл пошта тіркелген.');
   const c=b.admin_code?this.code(b.admin_code):null;
   if(c&&b.role!=='user')fail(400,'Әкімші коды пайдаланушы тіркеуімен қолданылады.');
   const uid=id(),role=c?'admin':b.role;
   this.run('INSERT INTO users(id,name,email,role,salt,hash,phone) VALUES(?,?,?,?,?,?,?)',uid,name,email,role,salt,hash,tel);
   if(c){this.run('UPDATE admin_codes SET uses=uses+1 WHERE id=?',c.id);this.audit(uid,'admin.grant',uid,{codeId:c.id});}
   return this.newSession(this.one('SELECT * FROM users WHERE id=?',uid));
  });
 }
 async login(b){const email=str(b.email,'Пошта',254).toLowerCase();if(typeof b.password!=='string'||b.password.length>128)fail(400,'Құпиясөзді енгізіңіз.');const u=this.one('SELECT * FROM users WHERE email=?',email);const h=await scrypt(b.password,u?.salt??'missing-user',64);if(!u||!u.active||!timingSafeEqual(h,Buffer.from(u.hash,'hex')))fail(401,'Пошта немесе құпиясөз қате.');return this.newSession(u);}
 teamView(t){return {...t,members:this.all('SELECT u.id,u.name,m.captain,m.joined_at FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.team_id=? AND u.active=1',t.id)};}
 saveTeam(u,b,teamId){this.require(u,['coach','admin']);const old=teamId?this.manage(u,teamId):null;
  const name=str(b.name??old?.name,'Команда',60),city=str(b.city??old?.city,'Қала',80),description=str(b.description??old?.description,'Сипаттама',1000),logo=optional(b.logo??old?.logo,2000);
  if(logo&&!/^https:\/\//.test(logo))fail(400,'Логотипке HTTPS сілтемесін енгізіңіз.');
  if(logo){try{const url=new URL(logo);if(url.username||url.password)fail(400,'Логотип сілтемесі қате.');}catch{fail(400,'Логотип сілтемесі қате.');}}
  const coach=u.role==='coach'?u.id:(b.coach_id??old?.coach_id??null);
  if(coach){const c=this.one("SELECT id FROM users WHERE id=? AND role='coach' AND active=1",coach);if(!c)fail(400,'Белсенді жаттықтырушыны таңдаңыз.');if(this.one('SELECT 1 FROM teams WHERE coach_id=? AND id<>?',coach,teamId??''))fail(409,'Жаттықтырушының командасы бар.');}
  const active=u.role==='admin'?integer(b.active??old?.active??1,0,1):(old?.active??1);
  return this.tx(()=>{const tid=teamId??id();if(old)this.run('UPDATE teams SET name=?,city=?,description=?,logo=?,active=?,coach_id=? WHERE id=?',name,city,description,logo,active,coach,tid);
   else this.run('INSERT INTO teams(id,coach_id,name,city,description,logo,active,created_at) VALUES(?,?,?,?,?,?,?,?)',tid,coach,name,city,description,logo,active,now());
   this.audit(u.id,old?'team.update':'team.create',tid);return {team:this.teamView(this.team(tid))};});
 }
 invite(u,tid,b){const t=this.manage(u,tid);if(!t.active)fail(409,'Команда белсенді емес.');const target=this.one("SELECT * FROM users WHERE id=? AND role='user' AND active=1",str(b.user_id,'Профиль ID'));
  if(!target)fail(404,'Тіркелген пайдаланушы табылмады.');return this.tx(()=>{
   if(this.one('SELECT 1 FROM invitations WHERE team_id=? AND user_id=?',tid,target.id)||this.one('SELECT 1 FROM memberships WHERE team_id=? AND user_id=?',tid,target.id))fail(409,'Бұл пайдаланушыға шақыру жіберілген.');
   const iid=id();this.run("INSERT INTO invitations(id,team_id,user_id,invited_by,status,created_at) VALUES(?,?,?,?,'pending',?)",iid,tid,target.id,u.id,now());
   this.run('INSERT INTO notifications(id,user_id,invitation_id,message,created_at) VALUES(?,?,?,?,?)',id(),target.id,iid,`${t.name} командасына шақыру`,now());
   return {ok:true};});
 }
 answer(u,iid,b){this.require(u);if(!['accepted','rejected'].includes(b.status))fail(400,'Жауапты таңдаңыз.');return this.tx(()=>{
  const inv=this.one('SELECT * FROM invitations WHERE id=? AND user_id=?',iid,u.id);if(!inv)fail(404,'Шақыру табылмады.');if(inv.status!=='pending')fail(409,'Шақыруға жауап берілген.');
  const t=this.team(inv.team_id);if(!t.active)fail(409,'Команда белсенді емес.');if(u.role!=='user')fail(403,'Ойыншы рөлі қажет.');
  if(b.status==='accepted')this.run('INSERT INTO memberships(team_id,user_id,joined_at) VALUES(?,?,?)',inv.team_id,u.id,now());
  this.run('UPDATE invitations SET status=?,responded_at=? WHERE id=?',b.status,now(),iid);this.run('UPDATE notifications SET read_at=? WHERE invitation_id=? AND user_id=?',now(),iid,u.id);return {ok:true};});
 }
 schedule(b,old={}){const best= b.best_of??old.best_of??5,format=b.format??old.format??'indoor';if(![1,3,5].includes(best)||!['indoor','beach'].includes(format))fail(400,'Матч форматы қате.');return {start_at:date(b.start_at??old.start_at),location:str(b.location??old.location,'Өтетін орын'),best_of:best,format};}
 conflicts(ids,at,except='',sameTournament=null){
  for(const m of this.all('SELECT * FROM matches WHERE start_at=? AND deleted=0 AND bye=0 AND id<>?',at,except)){
   if(sameTournament&&m.tournament_id===sameTournament)continue;
   const possible=[m.team_a,m.team_b].filter(Boolean);
   if(m.tournament_id&&(!m.team_a||!m.team_b))possible.push(...this.all('SELECT team_id FROM tournament_teams WHERE tournament_id=?',m.tournament_id).map(t=>t.team_id));
   if(ids.some(t=>possible.includes(t)))fail(409,'Осы уақытта команданың басқа матчы бар.');
  }
 }
 matchView(m){return {...m,a_name:m.team_a?this.one('SELECT name FROM teams WHERE id=?',m.team_a)?.name:null,b_name:m.team_b?this.one('SELECT name FROM teams WHERE id=?',m.team_b)?.name:null,winner_name:m.winner_id?this.one('SELECT name FROM teams WHERE id=?',m.winner_id)?.name:null};}
 tournament(tid){const t=this.one('SELECT * FROM tournaments WHERE id=? AND deleted=0',tid);if(!t)fail(404,'Турнир табылмады.');return t;}
 tournamentView(t){const teams=this.all('SELECT t.* FROM teams t JOIN tournament_teams e ON t.id=e.team_id WHERE e.tournament_id=? ORDER BY e.seed',t.id),matches=this.all('SELECT * FROM matches WHERE tournament_id=? ORDER BY round,position',t.id).map(m=>this.matchView(m));
  const rows=teams.map(t=>({team_id:t.id,name:t.name,played:0,wins:0,losses:0,points:0,sets_for:0,sets_against:0}));
  for(const m of matches.filter(m=>m.winner_id&&!m.bye&&!m.deleted)){for(const [tid,score,against] of [[m.team_a,m.score_a,m.score_b],[m.team_b,m.score_b,m.score_a]]){const r=rows.find(t=>t.team_id===tid);r.played++;r.sets_for+=score;r.sets_against+=against;if(m.winner_id===tid){r.wins++;r.points+=m.best_of===5&&against===2?2:3;}else{r.losses++;if(m.best_of===5&&score===2)r.points++;}}}
  rows.sort((a,b)=>b.points-a.points||b.wins-a.wins||(b.sets_for-b.sets_against)-(a.sets_for-a.sets_against)||a.name.localeCompare(b.name));
  return {...t,teams,matches,standings:rows};
 }
 saveTournament(u,b,tid){this.require(u,['admin']);const old=tid?this.tournament(tid):null,s=this.schedule(b,old??{});const kind=b.kind??old?.kind,title=str(b.title??old?.title,'Турнир');if(!['round_robin','playoff'].includes(kind))fail(400,'Турнир форматын таңдаңыз.');
  const interval=integer(b.round_minutes??old?.round_minutes??1440,30,525600);
  const ids=b.team_ids??(old?this.all('SELECT team_id FROM tournament_teams WHERE tournament_id=? ORDER BY seed',tid).map(t=>t.team_id):[]);if(!old?.generated)this.activeTeams(ids);
  if(old?.generated&&(kind!==old.kind||s.start_at!==old.start_at||s.best_of!==old.best_of||s.format!==old.format||interval!==old.round_minutes||JSON.stringify(ids)!==JSON.stringify(this.all('SELECT team_id FROM tournament_teams WHERE tournament_id=? ORDER BY seed',tid).map(t=>t.team_id))))fail(409,'Жасалған кестенің форматы мен құрамын өзгертуге болмайды. Матч уақытын жеке өзгертіңіз.');
  return this.tx(()=>{tid??=id();if(old)this.run('UPDATE tournaments SET title=?,location=?,kind=?,start_at=?,best_of=?,format=?,round_minutes=? WHERE id=?',title,s.location,kind,s.start_at,s.best_of,s.format,interval,tid);
   else this.run('INSERT INTO tournaments(id,title,kind,start_at,location,best_of,format,round_minutes,created_by,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',tid,title,kind,s.start_at,s.location,s.best_of,s.format,interval,u.id,now());
   if(!old?.generated){this.run('DELETE FROM tournament_teams WHERE tournament_id=?',tid);ids.forEach((v,i)=>this.run('INSERT INTO tournament_teams VALUES(?,?,?)',tid,v,i));}
   this.audit(u.id,old?'tournament.update':'tournament.create',tid);return {tournament:this.tournamentView(this.tournament(tid))};});
 }
 insertMatch(u,s,a,b,tid=null,round=1,position=0){const mid=id();this.run('INSERT INTO matches(id,tournament_id,round,position,team_a,team_b,start_at,location,format,best_of,created_by) VALUES(?,?,?,?,?,?,?,?,?,?,?)',mid,tid,round,position,a,b,s.start_at,s.location,s.format,s.best_of,u.id);return mid;}
 saveMatch(u,b,mid){this.require(u,['admin']);const old=mid?this.one('SELECT * FROM matches WHERE id=? AND deleted=0',mid):null;if(mid&&!old)fail(404,'Матч табылмады.');const s=this.schedule(b,old??{});
  const a=b.team_a??old?.team_a,c=b.team_b??old?.team_b;
  if(old?.tournament_id&&(a!==old.team_a||c!==old.team_b||s.best_of!==old.best_of||s.format!==old.format))fail(409,'Турнир матчының құрамы мен форматы бекітілген.');
  if(!old?.tournament_id)this.activeTeams([a,c]);else [a,c].filter(Boolean).forEach(v=>{if(!this.team(v).active)fail(409,'Команда белсенді емес.');});
  if(old?.winner_id)fail(409,'Аяқталған матчты өңдеу мүмкін емес.');
  return this.tx(()=>{let potential=[a,c].filter(Boolean);if(old?.tournament_id&&(!a||!c))potential=this.all('SELECT team_id FROM tournament_teams WHERE tournament_id=?',old.tournament_id).map(t=>t.team_id);
   if(!old||s.start_at!==old.start_at||a!==old.team_a||c!==old.team_b)this.conflicts(potential,s.start_at,mid??'');
   if(old){
    const preceding=this.all('SELECT start_at FROM matches WHERE next_match=?',mid);const following=old.next_match?this.one('SELECT start_at FROM matches WHERE id=?',old.next_match):null;
    if(preceding.some(m=>m.start_at>=s.start_at)||(following&&s.start_at>=following.start_at))fail(409,'Кезеңдердің уақыт ретін сақтаңыз.');
    this.run('UPDATE matches SET start_at=?,location=?,team_a=?,team_b=?,format=?,best_of=? WHERE id=?',s.start_at,s.location,a,c,s.format,s.best_of,mid);
   }else mid=this.insertMatch(u,s,a,c);
   this.audit(u.id,old?'match.update':'match.create',mid);return {match:this.matchView(this.one('SELECT * FROM matches WHERE id=?',mid))};});
 }
 generate(u,tid){this.require(u,['admin']);return this.tx(()=>{
  const t=this.tournament(tid);if(t.generated)fail(409,'Матчтар жасалған.');const ids=this.all('SELECT team_id FROM tournament_teams WHERE tournament_id=? ORDER BY seed',tid).map(v=>v.team_id);this.activeTeams(ids);
  const at=r=>({...t,start_at:new Date(Date.parse(t.start_at)+r*t.round_minutes*60000).toISOString()});
  if(t.kind==='round_robin'){
   const rotation=[...ids];if(rotation.length%2)rotation.push(null);
   for(let r=0;r<rotation.length-1;r++){
    for(let i=0;i<rotation.length/2;i++){const a=rotation[i],b=rotation[rotation.length-1-i];if(!a||!b)continue;this.conflicts([a,b],at(r).start_at,'',tid);this.insertMatch(u,at(r),a,b,tid,r+1,i);}
    rotation.splice(1,0,rotation.pop());
   }
  }else{
   const size=2**Math.ceil(Math.log2(ids.length)),paired=ids.length-size/2;let cursor=0;const rounds=[];
   for(let count=size/2,r=0;count>=1;count/=2,r++){
    this.conflicts(ids,at(r).start_at,'',tid);const list=[];
    for(let i=0;i<count;i++){const a=r===0?ids[cursor++]:null,b=r===0&&i<paired?ids[cursor++]:null;list.push(this.insertMatch(u,at(r),a,b,tid,r+1,i));}
    rounds.push(list);
   }
   for(let r=0;r<rounds.length-1;r++)rounds[r].forEach((mid,i)=>this.run('UPDATE matches SET next_match=?,next_slot=? WHERE id=?',rounds[r+1][Math.floor(i/2)],i%2?'team_b':'team_a',mid));
   for(const mid of rounds[0]){const m=this.one('SELECT * FROM matches WHERE id=?',mid);if(!m.team_b){this.run('UPDATE matches SET bye=1,winner_id=? WHERE id=?',m.team_a,mid);this.advance(m,m.team_a);}}
  }
  this.run('UPDATE tournaments SET generated=1 WHERE id=?',tid);this.audit(u.id,'tournament.generate',tid);return {tournament:this.tournamentView(this.tournament(tid))};
 });}
 advance(m,winner){if(m.next_match){const next=this.one('SELECT * FROM matches WHERE id=?',m.next_match);if(next.winner_id)fail(409,'Келесі матч аяқталған. Нәтижені өзгертуге болмайды.');if(winner)this.conflicts([winner],next.start_at,next.id,m.tournament_id);const slot=m.next_slot==='team_a'?'team_a':'team_b';this.run(`UPDATE matches SET ${slot}=? WHERE id=?`,winner,next.id);}}
 result(u,mid,b){this.require(u,['admin']);return this.tx(()=>{const m=this.one('SELECT * FROM matches WHERE id=? AND deleted=0',mid);if(!m||!m.team_a||!m.team_b||m.bye)fail(409,'Матч нәтижеге дайын емес.');const target=(m.best_of+1)/2,a=b.score_a,c=b.score_b;if(!Number.isInteger(a)||!Number.isInteger(c)||!((a===target&&c>=0&&c<target)||(c===target&&a>=0&&a<target)))fail(400,'Сеттер есебін тексеріңіз.');const winner=a>c?m.team_a:m.team_b;
   this.advance(m,winner);this.run('UPDATE matches SET score_a=?,score_b=?,winner_id=? WHERE id=?',a,c,winner,mid);this.audit(u.id,'match.result',mid,{score_a:a,score_b:c});return {match:this.matchView(this.one('SELECT * FROM matches WHERE id=?',mid))};});}
 deleteMatch(u,mid){this.require(u,['admin']);return this.tx(()=>{const m=this.one('SELECT * FROM matches WHERE id=? AND deleted=0',mid);if(!m)fail(404,'Матч табылмады.');this.advance(m,null);this.run('UPDATE matches SET deleted=1,winner_id=NULL,score_a=NULL,score_b=NULL WHERE id=?',mid);this.audit(u.id,'match.delete',mid);return {ok:true};});}
 async route(method,path,b,u,query){
  let m;
  if(path==='/register'&&method==='POST')return this.register(b);
  if(path==='/login'&&method==='POST')return this.login(b);
  if(path==='/me'&&method==='GET')return {user:safeUser(u),team:u?(this.one('SELECT * FROM teams WHERE coach_id=? AND deleted=0',u.id)??null):null};
  if(path==='/me'&&method==='PATCH'){this.require(u);this.run('UPDATE users SET name=?,phone=? WHERE id=?',str(b.name,'Аты-жөні',80),phone(b.phone),u.id);return {user:safeUser(this.one('SELECT * FROM users WHERE id=?',u.id))};}
  if(path==='/admin/redeem'&&method==='POST')return this.redeem(u,b.code);
  if(path==='/teams'&&method==='GET')return {teams:this.all('SELECT * FROM teams WHERE deleted=0 ORDER BY created_at DESC').map(t=>this.teamView(t))};
  if(path==='/teams'&&method==='POST')return this.saveTeam(u,b);
  if(path==='/search'&&method==='GET'){
   const q=str(query.get('q'),'Іздеу',100).toLocaleLowerCase();
   if(q.length<2)fail(400,'Кемінде 2 таңба енгізіңіз.');
   const teams=this.all('SELECT * FROM teams WHERE deleted=0 AND active=1 ORDER BY name').filter(t=>[t.name,t.city,t.description].some(v=>v.toLocaleLowerCase().includes(q))).slice(0,20).map(t=>this.teamView(t));
   const players=this.all("SELECT id,name,role FROM users WHERE active=1 AND role='user' ORDER BY name").map(p=>({...p,teams:this.all('SELECT t.id,t.name,t.city FROM memberships m JOIN teams t ON t.id=m.team_id WHERE m.user_id=? AND t.deleted=0 AND t.active=1',p.id)})).filter(p=>p.name.toLocaleLowerCase().includes(q)||p.teams.some(t=>t.name.toLocaleLowerCase().includes(q))).slice(0,20);
   return {teams,players};
  }
  m=path.match(/^\/players\/([^/]+)$/);
  if(m&&method==='GET'){
   const player=this.one("SELECT id,name,role FROM users WHERE id=? AND active=1 AND role='user'",m[1]);
   if(!player)fail(404,'Ойыншы табылмады.');
   return {player:{...player,teams:this.all('SELECT t.id,t.name,t.city,t.description,t.logo FROM memberships e JOIN teams t ON t.id=e.team_id WHERE e.user_id=? AND t.deleted=0 AND t.active=1',player.id)}};
  }
  if(path==='/users/search'&&method==='GET'){
   this.require(u,['coach','admin']);if(u.role==='coach'&&!this.one('SELECT 1 FROM teams WHERE coach_id=? AND deleted=0 AND active=1',u.id))fail(403,'Алдымен командаңызды жасаңыз.');
   const q=str(query.get('q'),'Іздеу',100).toLocaleLowerCase();if(q.length<2)fail(400,'Кемінде 2 таңба енгізіңіз.');
   const digits=q.replace(/[\s()+-]/g,'');
   return {users:this.all("SELECT id,name,email,phone,role FROM users WHERE active=1 AND role='user'").filter(v=>[v.name,v.email,v.id,v.phone].some(s=>s.toLocaleLowerCase().includes(q))||(/^\d{3,}$/.test(digits)&&v.phone.includes(digits))).slice(0,20)};
  }
  m=path.match(/^\/teams\/([^/]+)(?:\/(invitations|members)(?:\/([^/]+))?)?$/);
  if(m){const tid=m[1];if(!m[2]){
   if(method==='GET')return {team:this.teamView(this.team(tid))};
   if(method==='PATCH')return this.saveTeam(u,b,tid);
   if(method==='DELETE'){this.require(u,['admin']);return this.tx(()=>{this.team(tid);this.run('UPDATE teams SET active=0,deleted=1,coach_id=NULL WHERE id=?',tid);this.run("UPDATE invitations SET status='cancelled',responded_at=? WHERE team_id=? AND status='pending'",now(),tid);this.audit(u.id,'team.delete',tid);return {ok:true};});}
  }
   if(m[2]==='invitations'&&method==='POST')return this.invite(u,tid,b);
   if(m[2]==='invitations'&&method==='GET'){this.manage(u,tid);return {invitations:this.all('SELECT i.*,u.name FROM invitations i JOIN users u ON i.user_id=u.id WHERE i.team_id=?',tid)};}
   if(m[2]==='members'&&m[3]){this.manage(u,tid);if(!this.one('SELECT 1 FROM memberships WHERE team_id=? AND user_id=?',tid,m[3]))fail(404,'Ойыншы командада жоқ.');return this.tx(()=>{
    if(method==='DELETE')this.run('DELETE FROM memberships WHERE team_id=? AND user_id=?',tid,m[3]);
    else if(method==='PATCH'){integer(b.captain,0,1);if(b.captain)this.run('UPDATE memberships SET captain=0 WHERE team_id=?',tid);this.run('UPDATE memberships SET captain=? WHERE team_id=? AND user_id=?',b.captain,tid,m[3]);}
    else fail(405,'Әдіс қолжетімсіз.');return {ok:true};});}
  }
  if(path==='/invitations'&&method==='GET'){this.require(u);return {invitations:this.all('SELECT i.*,t.name AS team_name FROM invitations i JOIN teams t ON t.id=i.team_id WHERE i.user_id=? ORDER BY i.created_at DESC',u.id)};}
  m=path.match(/^\/invitations\/([^/]+)$/);if(m&&method==='PATCH')return this.answer(u,m[1],b);
  if(path==='/notifications'&&method==='GET'){this.require(u);return {notifications:this.all('SELECT * FROM notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 100',u.id)};}
  m=path.match(/^\/notifications\/([^/]+)\/read$/);if(m&&method==='POST'){this.require(u);this.run('UPDATE notifications SET read_at=? WHERE id=? AND user_id=?',now(),m[1],u.id);return {ok:true};}
  if(path==='/matches'&&method==='GET')return {matches:this.all('SELECT * FROM matches WHERE deleted=0 ORDER BY start_at,round,position').map(m=>this.matchView(m))};
  if(path==='/matches'&&method==='POST')return this.saveMatch(u,b);
  m=path.match(/^\/matches\/([^/]+)(?:\/(result))?$/);if(m){if(m[2]&&method==='POST')return this.result(u,m[1],b);if(method==='PATCH')return this.saveMatch(u,b,m[1]);if(method==='DELETE')return this.deleteMatch(u,m[1]);}
  if(path==='/tournaments'&&method==='GET')return {tournaments:this.all('SELECT * FROM tournaments WHERE deleted=0 ORDER BY created_at DESC').map(t=>this.tournamentView(t))};
  if(path==='/tournaments'&&method==='POST')return this.saveTournament(u,b);
  m=path.match(/^\/tournaments\/([^/]+)(?:\/(generate))?$/);if(m){if(m[2]&&method==='POST')return this.generate(u,m[1]);if(method==='GET')return {tournament:this.tournamentView(this.tournament(m[1]))};if(method==='PATCH')return this.saveTournament(u,b,m[1]);if(method==='DELETE'){this.require(u,['admin']);return this.tx(()=>{this.tournament(m[1]);this.run('UPDATE tournaments SET deleted=1 WHERE id=?',m[1]);this.run('UPDATE matches SET deleted=1 WHERE tournament_id=?',m[1]);this.audit(u.id,'tournament.delete',m[1]);return {ok:true};});}}
  if(path.startsWith('/admin/')){
   this.require(u,['admin']);
   if(path==='/admin/codes'&&method==='POST')return this.issueCode(u,b);
   if(path==='/admin/codes'&&method==='GET')return {codes:this.all('SELECT id,created_by,expires,max_uses,uses,revoked,created_at FROM admin_codes ORDER BY created_at DESC')};
   m=path.match(/^\/admin\/codes\/([^/]+)$/);if(m&&method==='DELETE')return this.tx(()=>{if(!this.one('SELECT 1 FROM admin_codes WHERE id=?',m[1]))fail(404,'Код табылмады.');this.run('UPDATE admin_codes SET revoked=1 WHERE id=?',m[1]);this.audit(u.id,'admin_code.revoke',m[1]);return {ok:true};});
   if(path==='/admin/audit'&&method==='GET')return {events:this.all('SELECT * FROM audit_log ORDER BY id DESC LIMIT 200')};
   if(path==='/admin/users'&&method==='GET')return {users:this.all('SELECT id,name,email,role,phone,active FROM users ORDER BY name')};
   if(path==='/admin/legacy'&&method==='GET')return {tournaments:this.one("SELECT 1 FROM sqlite_master WHERE name='legacy_tournaments'")?this.all('SELECT * FROM legacy_tournaments').map(t=>JSON.parse(t.data)):[]};
   m=path.match(/^\/admin\/users\/([^/]+)$/);if(m&&method==='PATCH')return this.tx(()=>{const target=this.one('SELECT * FROM users WHERE id=?',m[1]);if(!target)fail(404,'Пайдаланушы табылмады.');if(b.role!=null)fail(400,'Әкімші құқығы тек код арқылы беріледі.');const active=integer(b.active??target.active,0,1);if(!active&&target.role==='admin'&&this.one("SELECT count(*) AS n FROM users WHERE role='admin' AND active=1").n<=1)fail(409,'Соңғы әкімшіні бұғаттауға болмайды.');this.run('UPDATE users SET active=?,name=?,phone=? WHERE id=?',active,str(b.name??target.name,'Аты-жөні',80),phone(b.phone??target.phone),target.id);if(!active)this.run('DELETE FROM sessions WHERE user_id=?',target.id);this.audit(u.id,'user.update',target.id,{active});return {user:safeUser(this.one('SELECT * FROM users WHERE id=?',target.id))};});
  }
  fail(404,'Бет табылмады.');
 }
}
