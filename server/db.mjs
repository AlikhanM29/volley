import {DatabaseSync} from 'node:sqlite';
import {existsSync,mkdirSync,readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const here=dirname(fileURLToPath(import.meta.url));
export const defaultDb=resolve(here,'data/volley.sqlite');
export function transaction(db,fn) {
 db.exec('BEGIN IMMEDIATE');
 try {const result=fn();db.exec('COMMIT');return result;} catch(e){db.exec('ROLLBACK');throw e;}
}
export function openDb(path=process.env.DB_PATH||defaultDb) {
 mkdirSync(dirname(path),{recursive:true});
 const existed=existsSync(path); const db=new DatabaseSync(path);
 // DELETE journaling keeps changes in the main .sqlite file so desktop
 // SQLite viewers immediately see newly saved teams, players and matches.
 db.exec('PRAGMA foreign_keys=ON; PRAGMA journal_mode=DELETE; PRAGMA busy_timeout=5000;');
 db.exec('CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY,applied_at TEXT NOT NULL)');
 if (!db.prepare('SELECT 1 FROM schema_migrations WHERE version=1').get()) {
   const legacy=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'").get();
   if(existed && legacy) db.exec(`VACUUM INTO '${(path+'.pre-v2-'+Date.now()+'.sqlite').replaceAll("'","''")}'`);
   transaction(db,()=>{
     const oldTournament=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='tournaments'").get();
     if(oldTournament && db.prepare('PRAGMA table_info(tournaments)').all().some(c=>c.name==='data')) db.exec('ALTER TABLE tournaments RENAME TO legacy_tournaments');
     db.exec(readFileSync(resolve(here,'migrations/001_platform.sql'),'utf8'));
     const cols=db.prepare('PRAGMA table_info(users)').all().map(c=>c.name);
     if(!cols.includes('phone'))db.exec("ALTER TABLE users ADD COLUMN phone TEXT NOT NULL DEFAULT ''");
     if(!cols.includes('active'))db.exec('ALTER TABLE users ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
     db.exec("UPDATE users SET role='user' WHERE role NOT IN ('user','coach','admin')");
     db.exec(`CREATE TRIGGER valid_role_insert BEFORE INSERT ON users WHEN NEW.role NOT IN ('user','coach','admin') BEGIN SELECT RAISE(ABORT,'invalid role'); END;
       CREATE TRIGGER valid_role_update BEFORE UPDATE OF role ON users WHEN NEW.role NOT IN ('user','coach','admin') BEGIN SELECT RAISE(ABORT,'invalid role'); END;`);
     db.prepare('INSERT INTO schema_migrations VALUES(1,?)').run(new Date().toISOString());
     db.prepare('INSERT INTO audit_log(action,details,created_at) VALUES(?,?,?)').run('schema.migrate',JSON.stringify({version:1,legacyPreserved:!!oldTournament}),new Date().toISOString());
   });
 }
 return db;
}
