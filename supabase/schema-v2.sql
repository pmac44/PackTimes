-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — location sharing, schema v2  (13 July 2026)
--  SUPERSEDES schema-v1.sql and schema-v2-patch.sql — delete those.
--
--  ⚠ THIS DROPS THE v1 TABLES AND REBUILDS THEM. Safe on 13 Jul 2026 (nothing
--    in there but a test share). NOT safe to re-run once real rides exist.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  THE MODEL, in plain English:
--
--    SHARE      = you. One row, one secret WRITE TOKEN, lives on your phone.
--                 Your phone pushes its position ONCE per interval, no matter
--                 how many people are watching.
--
--    VIEW LINK  = one window onto that share. Many per rider. Each has its own
--                 8-char public code, its own name, its own expiry, and can be
--                 revoked on its own without touching the others.
--
--                   "Jenny"              → never expires. Permanent.
--                   "Bent 400 organisers"→ pinned to ONE ride_id, expires 48h
--                                          after it. Cannot show them anything
--                                          else, ever, even by accident.
--
--    POSITION   = one GPS fix, tagged with the ride_id it belongs to.
--
--  SECURITY. The publishable key sits in index.html, which is public on GitHub,
--  so assume everyone has it. Both tables therefore have Row Level Security ON
--  with NO policies — the public key cannot read or write them directly, at
--  all. Every access goes through the functions below, which run as owner and
--  each do exactly one narrow job. Holding a view link lets you WATCH, and
--  nothing else: there is no code path that returns a write_token.
--
--  Guessing a view code is 32^8 ≈ 1.1 trillion tries.
--
--  Accepted limit: anyone with the publishable key can call share_init() and
--  make junk shares. Costs us rows and nothing else. Rate-limit if it ever
--  matters.
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

drop table if exists positions  cascade;
drop table if exists view_links cascade;
drop table if exists shares     cascade;

-- ── Tables ────────────────────────────────────────────────────────────────

create table shares (
  id            uuid primary key default gen_random_uuid(),
  write_token   text unique not null,     -- SECRET. Phone only. Never returned by share_view.
  label         text,                     -- "Peter" — what a viewer sees
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz               -- when the last position landed
);

create table view_links (
  id          uuid primary key default gen_random_uuid(),
  share_id    uuid not null references shares(id) on delete cascade,
  view_code   text unique not null,       -- PUBLIC. Goes in the link.
  name        text,                       -- "Jenny" — so YOU know who this link went to
  ride_id     text,                       -- null = follows every ride (permanent)
                                          -- set  = pinned to this one ride only
  expires_at  timestamptz,                -- null = never expires
  revoked_at  timestamptz,
  created_at  timestamptz not null default now()
);

create index view_links_share on view_links (share_id);

create table positions (
  id          bigserial primary key,
  share_id    uuid not null references shares(id) on delete cascade,
  ride_id     text,
  lat         double precision not null,
  lon         double precision not null,
  ele         real,
  speed       real,                       -- km/h
  dist_km     real,                       -- distance along the route, if following one
  t           timestamptz not null,       -- time of the GPS fix (device clock)
  created_at  timestamptz not null default now()
);

create index positions_share_ride_t on positions (share_id, ride_id, t desc);

alter table shares     enable row level security;
alter table view_links enable row level security;
alter table positions  enable row level security;
-- No policies. The public key cannot touch these tables directly.

-- ── Helper: short human-safe code ─────────────────────────────────────────
-- 32-char alphabet, no 0/O/1/I (misread on a phone screen). Crypto RNG, not
-- random(), so codes aren't predictable.
-- NOTE: search_path must include `extensions` — that's where pgcrypto lives on
-- Supabase. Without it: "gen_random_bytes does not exist".

create or replace function pt_code(n int)
returns text
language plpgsql
set search_path = public, extensions
as $$
declare
  a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea := gen_random_bytes(n);
  r text := '';
  i int;
begin
  for i in 1..n loop
    r := r || substr(a, 1 + (get_byte(b, i - 1) % 32), 1);
  end loop;
  return r;
end $$;

-- ── share_init — called ONCE per rider, ever ──────────────────────────────
-- Returns the write token. This is the only time it is ever handed out; after
-- this it lives on the phone and nothing can read it back.

create or replace function share_init(p_label text default null)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  w text := encode(gen_random_bytes(24), 'hex');
begin
  insert into shares (write_token, label) values (w, nullif(p_label, ''));
  return w;
end $$;

-- ── share_set_label ───────────────────────────────────────────────────────

create or replace function share_set_label(p_write_token text, p_label text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update shares set label = nullif(p_label, '') where write_token = p_write_token;
end $$;

-- ── link_create — mint a new view link ────────────────────────────────────
--   p_ride_id    null → permanent, follows every ride ("Jenny")
--                set  → pinned to that one ride ("Bent 400 organisers")
--   p_expires_at null → never expires

create or replace function link_create(
  p_write_token text,
  p_name        text        default null,
  p_ride_id     text        default null,
  p_expires_at  timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  v   text;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  loop
    v := pt_code(8);
    exit when not exists (select 1 from view_links l where l.view_code = v);
  end loop;

  insert into view_links (share_id, view_code, name, ride_id, expires_at)
  values (sid, v, nullif(p_name, ''), nullif(p_ride_id, ''), p_expires_at);

  return v;
end $$;

-- ── link_list — what links do I have out there? ───────────────────────────

create or replace function link_list(p_write_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  res jsonb;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'viewCode',  l.view_code,
           'name',      l.name,
           'rideId',    l.ride_id,
           'expiresAt', l.expires_at,
           'revokedAt', l.revoked_at,
           'createdAt', l.created_at
         ) order by l.created_at), '[]'::jsonb)
    into res
    from view_links l
   where l.share_id = sid;

  return res;
end $$;

-- ── link_revoke — kill one link, leave the others alone ───────────────────

create or replace function link_revoke(p_write_token text, p_view_code text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  update view_links
     set revoked_at = now()
   where share_id = sid
     and view_code = upper(p_view_code)
     and revoked_at is null;
end $$;

-- ── share_push — one GPS fix. Needs the write token. ──────────────────────
-- One push feeds every link. The phone does not care who is watching.

create or replace function share_push(
  p_write_token text,
  p_ride_id     text,
  p_lat         double precision,
  p_lon         double precision,
  p_ele         real        default null,
  p_speed       real        default null,
  p_dist_km     real        default null,
  p_t           timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  insert into positions (share_id, ride_id, lat, lon, ele, speed, dist_km, t)
  values (sid, nullif(p_ride_id, ''), p_lat, p_lon, p_ele, p_speed, p_dist_km,
          coalesce(p_t, now()));

  update shares set last_seen_at = now() where id = sid;
end $$;

-- ── share_view — the ONLY thing PackView calls ────────────────────────────
-- Takes a public view code. Returns the label, the timestamps, and the trail.
-- Trail points are packed as arrays to keep the payload small:
--   [lat, lon, epoch_ms, speed, dist_km]
--
-- Which ride does it show?
--   link pinned to a ride → that ride, and only ever that ride
--   permanent link        → whatever ride the rider is on most recently
--
-- "Are they riding right now?" is answered by lastSeenAt, not a flag. The
-- viewer decides how to phrase it — a fix 2 minutes old means moving; 6 hours
-- old means they're not on the bike.

create or replace function share_view(
  p_view_code text,
  p_trail     int default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  l   view_links%rowtype;
  s   shares%rowtype;
  rid text;
  res jsonb;
begin
  select * into l from view_links where view_code = upper(p_view_code);

  if l.id is null
     or l.revoked_at is not null
     or (l.expires_at is not null and l.expires_at < now()) then
    return jsonb_build_object('error', 'not_found');
  end if;

  select * into s from shares where id = l.share_id;

  if l.ride_id is not null then
    rid := l.ride_id;                    -- pinned link: this ride, only ever
  else
    select p.ride_id into rid            -- permanent link: their current ride
      from positions p
     where p.share_id = s.id
     order by p.t desc
     limit 1;
  end if;

  select jsonb_build_object(
    'label',      s.label,
    'linkName',   l.name,
    'rideId',     rid,
    'lastSeenAt', (select max(p.t) from positions p
                    where p.share_id = s.id
                      and p.ride_id is not distinct from rid),
    'expiresAt',  l.expires_at,
    'trail', coalesce((
      select jsonb_agg(
               jsonb_build_array(
                 p.lat, p.lon,
                 (extract(epoch from p.t) * 1000)::bigint,
                 p.speed, p.dist_km
               ) order by p.t
             )
        from (
          select * from positions
           where share_id = s.id
             and ride_id is not distinct from rid
           order by t desc
           limit greatest(1, least(p_trail, 2000))
        ) p
    ), '[]'::jsonb)
  ) into res;

  return res;
end $$;

-- ── Permissions ───────────────────────────────────────────────────────────
-- `anon` is the role the publishable key maps to. It may call these functions
-- and nothing else. It cannot call pt_code, and it cannot see the tables.

revoke execute on function pt_code(int) from public, anon;

grant execute on function share_init(text)                            to anon, authenticated;
grant execute on function share_set_label(text, text)                 to anon, authenticated;
grant execute on function link_create(text, text, text, timestamptz)  to anon, authenticated;
grant execute on function link_list(text)                             to anon, authenticated;
grant execute on function link_revoke(text, text)                     to anon, authenticated;
grant execute on function share_push(text, text, double precision, double precision, real, real, real, timestamptz) to anon, authenticated;
grant execute on function share_view(text, int)                       to anon, authenticated;
