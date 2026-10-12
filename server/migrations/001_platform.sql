CREATE TABLE IF NOT EXISTS users (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL,
 role TEXT NOT NULL CHECK(role IN ('user','coach','admin')), salt TEXT NOT NULL, hash TEXT NOT NULL,
 phone TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1))
);
CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
CREATE TABLE teams (
 id TEXT PRIMARY KEY, coach_id TEXT UNIQUE REFERENCES users(id), name TEXT NOT NULL,
 city TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', logo TEXT NOT NULL DEFAULT '',
 active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), deleted INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL
);
CREATE TABLE memberships (
 team_id TEXT NOT NULL REFERENCES teams(id), user_id TEXT NOT NULL REFERENCES users(id),
 captain INTEGER NOT NULL DEFAULT 0 CHECK(captain IN (0,1)), joined_at TEXT NOT NULL,
 PRIMARY KEY(team_id,user_id)
);
CREATE UNIQUE INDEX one_captain ON memberships(team_id) WHERE captain=1;
CREATE TABLE invitations (
 id TEXT PRIMARY KEY,team_id TEXT NOT NULL REFERENCES teams(id),user_id TEXT NOT NULL REFERENCES users(id),
 invited_by TEXT NOT NULL REFERENCES users(id),status TEXT NOT NULL CHECK(status IN ('pending','accepted','rejected','cancelled')),
 created_at TEXT NOT NULL,responded_at TEXT,UNIQUE(team_id,user_id)
);
CREATE TABLE notifications (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),invitation_id TEXT REFERENCES invitations(id),
 message TEXT NOT NULL,read_at TEXT,created_at TEXT NOT NULL
);
CREATE TABLE admin_codes (
 id TEXT PRIMARY KEY,hash TEXT NOT NULL UNIQUE,created_by TEXT REFERENCES users(id),
 expires INTEGER NOT NULL,max_uses INTEGER NOT NULL CHECK(max_uses BETWEEN 1 AND 20),
 uses INTEGER NOT NULL DEFAULT 0,revoked INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,
 CHECK(uses>=0 AND uses<=max_uses)
);
CREATE TABLE audit_log (
 id INTEGER PRIMARY KEY AUTOINCREMENT,actor_id TEXT REFERENCES users(id),
 action TEXT NOT NULL,target_id TEXT,details TEXT NOT NULL DEFAULT '{}',created_at TEXT NOT NULL
);
CREATE TABLE tournaments (
 id TEXT PRIMARY KEY,title TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('round_robin','playoff')),
 start_at TEXT NOT NULL,location TEXT NOT NULL,best_of INTEGER NOT NULL CHECK(best_of IN (1,3,5)),
 format TEXT NOT NULL CHECK(format IN ('indoor','beach')),round_minutes INTEGER NOT NULL CHECK(round_minutes>=30),
 generated INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,
 created_by TEXT NOT NULL REFERENCES users(id),created_at TEXT NOT NULL
);
CREATE TABLE tournament_teams (
 tournament_id TEXT NOT NULL REFERENCES tournaments(id),team_id TEXT NOT NULL REFERENCES teams(id),
 seed INTEGER NOT NULL,PRIMARY KEY(tournament_id,team_id),UNIQUE(tournament_id,seed)
);
CREATE TABLE matches (
 id TEXT PRIMARY KEY,tournament_id TEXT REFERENCES tournaments(id),round INTEGER NOT NULL DEFAULT 1,position INTEGER NOT NULL DEFAULT 0,
 team_a TEXT REFERENCES teams(id),team_b TEXT REFERENCES teams(id),start_at TEXT NOT NULL,location TEXT NOT NULL,
 format TEXT NOT NULL CHECK(format IN ('indoor','beach')),best_of INTEGER NOT NULL CHECK(best_of IN (1,3,5)),
 score_a INTEGER,score_b INTEGER,winner_id TEXT REFERENCES teams(id),bye INTEGER NOT NULL DEFAULT 0,
 next_match TEXT REFERENCES matches(id),next_slot TEXT CHECK(next_slot IN ('team_a','team_b')),
 deleted INTEGER NOT NULL DEFAULT 0,created_by TEXT NOT NULL REFERENCES users(id),
 CHECK(team_a IS NULL OR team_b IS NULL OR team_a<>team_b)
);
CREATE INDEX match_schedule ON matches(start_at,deleted);
CREATE INDEX invitation_inbox ON invitations(user_id,status);
CREATE INDEX notifications_inbox ON notifications(user_id,created_at);
