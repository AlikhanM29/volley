// VS Code pre-launch task: reuse a healthy server or start it in this terminal.
import {createApp} from './server.mjs';

console.log('VOLLEY_STARTING');
let running = false;
try {
  const response = await fetch('http://127.0.0.1:8080/api/health', {signal: AbortSignal.timeout(2000)});
  const data = await response.json();
  if (response.ok && data.service === 'volley' && data.version !== 2) {
    console.error('Older Volley server is running. Stop its VS Code task/terminal and press F5 again.');
    process.exit(1);
  }
  running = response.ok && data.service === 'volley' && data.version === 2 && data.ok === true;
} catch { /* No healthy server yet. */ }

if (running) {
  console.log('Volley server is already running at http://localhost:8080');
  console.log('VOLLEY_READY');
} else {
  const {server, db} = createApp();
  server.on('error', error => {
    console.error(error.code === 'EADDRINUSE'
      ? 'Port 8080 is occupied by another or older server. Stop that server, then press F5 again.'
      : `Unable to start Volley: ${error.message}`);
    db.close(); process.exitCode = 1;
  });
  server.listen(8080, '127.0.0.1', () => {
    console.log('Volley server: http://localhost:8080');
    console.log('VOLLEY_READY');
  });
  const shutdown = () => server.close(() => { db.close(); process.exit(0); });
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}
