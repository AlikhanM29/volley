import {openDb} from './db.mjs';
import {Platform} from './platform.mjs';
if(!process.argv.includes('--bootstrap')){console.error('Usage: node server/admin-code.mjs --bootstrap');process.exit(1);}
const db=openDb();
try { const result=new Platform(db).issueCode(null,{},true);console.log('Initial admin code (one use, valid 24 hours; shown once):\n'+result.code); }
catch(e){console.error(e.message);process.exitCode=1;}finally{db.close();}
