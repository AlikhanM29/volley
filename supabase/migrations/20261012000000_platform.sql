-- Volley: Supabase/PostgreSQL schema.
-- Run this migration in a Supabase project. Application users come from auth.users.

create extension if not exists pgcrypto;

create type public.user_role as enum ('user', 'coach', 'admin');
create type public.invitation_status as enum ('pending', 'accepted', 'rejected', 'cancelled');
create type public.tournament_kind as enum ('round_robin', 'playoff');
create type public.volley_format as enum ('indoor', 'beach');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  phone text not null default '',
  role public.user_role not null default 'user',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid unique references public.profiles(id) on delete set null,
  name text not null,
  city text not null,
  description text not null default '',
  logo text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.memberships (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  captain boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create unique index memberships_one_captain on public.memberships(team_id) where captain;

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  invited_by uuid not null references public.profiles(id) on delete restrict,
  status public.invitation_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (team_id, user_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  invitation_id uuid references public.invitations(id) on delete cascade,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.admin_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  created_by uuid references public.profiles(id) on delete set null,
  expires_at timestamptz not null,
  max_uses integer not null check (max_uses between 1 and 20),
  uses integer not null default 0 check (uses >= 0 and uses <= max_uses),
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind public.tournament_kind not null,
  start_at timestamptz not null,
  location text not null,
  best_of integer not null check (best_of in (1, 3, 5)),
  format public.volley_format not null,
  round_minutes integer not null check (round_minutes >= 30),
  generated boolean not null default false,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.tournament_teams (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete restrict,
  seed integer not null,
  primary key (tournament_id, team_id),
  unique (tournament_id, seed)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid references public.tournaments(id) on delete cascade,
  round integer not null default 1,
  position integer not null default 0,
  team_a uuid references public.teams(id) on delete restrict,
  team_b uuid references public.teams(id) on delete restrict,
  start_at timestamptz not null,
  location text not null,
  format public.volley_format not null,
  best_of integer not null check (best_of in (1, 3, 5)),
  score_a integer check (score_a >= 0),
  score_b integer check (score_b >= 0),
  winner_id uuid references public.teams(id) on delete restrict,
  bye boolean not null default false,
  next_match uuid references public.matches(id) on delete set null,
  next_slot text check (next_slot in ('team_a', 'team_b')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (team_a is null or team_b is null or team_a <> team_b),
  check (winner_id is null or winner_id = team_a or winner_id = team_b)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index invitations_inbox on public.invitations(user_id, status);
create index notifications_inbox on public.notifications(user_id, created_at desc);
create index matches_schedule on public.matches(start_at);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and active); $$;

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.memberships enable row level security;
alter table public.invitations enable row level security;
alter table public.notifications enable row level security;
alter table public.admin_codes enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_teams enable row level security;
alter table public.matches enable row level security;
alter table public.audit_log enable row level security;

create policy "Public profiles are readable" on public.profiles for select using (true);
create policy "Users update own profile" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id and role = (select role from public.profiles where id = auth.uid()));
create policy "Teams are readable" on public.teams for select using (true);
create policy "Admins manage teams" on public.teams for all using (public.is_admin()) with check (public.is_admin());
create policy "Coaches create own team" on public.teams for insert with check (auth.uid() = coach_id and (select role from public.profiles where id = auth.uid()) = 'coach');
create policy "Coaches manage own team" on public.teams for update using (auth.uid() = coach_id) with check (auth.uid() = coach_id);
create policy "Memberships are readable" on public.memberships for select using (true);
create policy "Coach or admin manages memberships" on public.memberships for all using (public.is_admin() or exists (select 1 from public.teams where teams.id = memberships.team_id and teams.coach_id = auth.uid())) with check (public.is_admin() or exists (select 1 from public.teams where teams.id = memberships.team_id and teams.coach_id = auth.uid()));
create policy "Invitation recipient reads own invitations" on public.invitations for select using (auth.uid() = user_id or public.is_admin() or exists (select 1 from public.teams where teams.id = invitations.team_id and teams.coach_id = auth.uid()));
create policy "Coach creates invitations" on public.invitations for insert with check (auth.uid() = invited_by and exists (select 1 from public.teams where teams.id = team_id and teams.coach_id = auth.uid()));
create policy "Recipient responds to invitation" on public.invitations for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users read own notifications" on public.notifications for select using (auth.uid() = user_id);
create policy "Users update own notifications" on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Tournaments are readable" on public.tournaments for select using (true);
create policy "Admins manage tournaments" on public.tournaments for all using (public.is_admin()) with check (public.is_admin());
create policy "Tournament teams are readable" on public.tournament_teams for select using (true);
create policy "Admins manage tournament teams" on public.tournament_teams for all using (public.is_admin()) with check (public.is_admin());
create policy "Matches are readable" on public.matches for select using (true);
create policy "Admins manage matches" on public.matches for all using (public.is_admin()) with check (public.is_admin());
create policy "Admins manage codes" on public.admin_codes for all using (public.is_admin()) with check (public.is_admin());
create policy "Admins read audit log" on public.audit_log for select using (public.is_admin());

