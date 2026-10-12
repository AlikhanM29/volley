import {openDb} from './db.mjs';
const db=openDb();
console.log('Applied migrations:',db.prepare('SELECT * FROM schema_migrations ORDER BY version').all());
db.close();
