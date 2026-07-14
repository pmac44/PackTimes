-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — PackRide events, schema v5  (13 July 2026)
--  ADDITIVE. Drops no tables. Run AFTER schema-v4.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  WHAT THIS ADDS: the EVENT. Until now a share was one rider broadcasting to
--  watchers. An event is many riders broadcasting into one pool, all seeing each
--  other. It is the only genuinely new primitive in PackRide — everything else on
--  the feature list (navigation, turn cues, recording, stops, Strava) already
--  exists, and everything else in the backend (shares, tokens, routes, positions)
--  is reused unchanged.
--
--  THE MODEL:
--    event         — one route, one start time, one code (e.g. 7K2PBENT). Created
--                    by a rider; carries the organiser's chosen preset and update
--                    interval, so joiners inherit both without being asked.
--    event_member  — a rider in the event, with a display name.
--    rides.event_id— which event a ride belongs to. Positions are already tagged
--                    with ride_id, so this is what puts a rider's dots in a pack.
--
--  IDENTITY. A joining rider REUSES THE SHARE AND WRITE TOKEN THEY ALREADY HAVE.
--  One person, one identity, across every ride and every event. No accounts, no
--  signup, nothing to log into. A rider who has never shared before gets a token
--  minted on join (share_init) — same path as before.
--
--  VISIBILITY. Everyone in the event sees everyone (Peter, 13 Jul 2026 — a bunch
--  ride is not hub-and-spoke). The event code is PUBLIC: it is the link you paste
--  into a group chat. Holding it lets you WATCH the pack (that's the spectator
--  case) and lets you JOIN (that's the rider case). It does not let you write as
--  anyone else — that still needs their secret token, which never leaves the phone.
--
--  ACCEPTED LIMIT: anyone with the event code can join and appear as a rider. For
--  a bunch ride shared in a WhatsApp group that is exactly right. A public race
--  would eventually want the organiser to vet entries — add an `approval_required`
--  flag and a pending state on event_members. The tables have room. Not now.
--
--  PLACINGS ARE FREE. Every position already carries dist_km (distance along the
--  route, computed on the rider's phone by snapTo). So the leaderboard is a sort,
--  not new maths.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Tables ────────────────────────────────────────────────────────────────

create table if not exists events (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,        -- PUBLIC. The invite link.
  name         text not null,
  organiser_id uuid not null references shares(id) on delete cascade,
  route_id     uuid references routes(id) on delete set null,
  start_at     timestamptz,
  preset       text not null default 'ride',   -- 'ride' | 'bigday' | 'full'  (§3.7)
  interval_s   int  not null default 30,       -- organiser's call, applies to EVERYONE
  created_at   timestamptz not null default now()
);

create table if not exists event_members (
  event_id     uuid not null references events(id) on delete cascade,
  share_id     uuid not null references shares(id) on delete cascade,
  display_name text,
  is_organiser boolean not null default false,
  joined_at    timestamptz not null default now(),
  primary key (event_id, share_id)
);

-- Which event a ride belongs to. Positions are already tagged with ride_id, so this
-- one column is what turns a set of lone riders into a pack.
alter table rides add column if not exists event_id uuid references events(id) on delete set null;
create index if not exists rides_event on rides (event_id);

alter table events        enable row level security;
alter table event_members enable row level security;
-- No policies, as everywhere else. The public key cannot touch the tables.

-- ── event_create ──────────────────────────────────────────────────────────
-- The route must already be up (call route_ensure first). p_route_key null = a
-- social ride with no route: perfectly valid, the pack map just has no line on it.

create or replace function event_create(
  p_write_token text,
  p_name        text,
  p_route_key   text        default null,
  p_start_at    timestamptz default null,
  p_preset      text        default 'ride',
  p_interval_s  int         default 30
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  rt  uuid;
  c   text;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  if p_route_key is not null then
    select id into rt from routes where share_id = sid and route_key = p_route_key;
  end if;

  loop
    c := pt_code(8);
    exit when not exists (select 1 from events e where e.code = c);
  end loop;

  insert into events (code, name, organiser_id, route_id, start_at, preset, interval_s)
  values (c, coalesce(nullif(p_name,''),'Group ride'), sid, rt, p_start_at,
          coalesce(nullif(p_preset,''),'ride'), greatest(5, least(coalesce(p_interval_s,30), 600)));

  insert into event_members (event_id, share_id, display_name, is_organiser)
  select e.id, sid, s.label, true
    from events e, shares s
   where e.code = c and s.id = sid;

  return c;
end $$;

-- ── event_info — the JOIN SCREEN. Public; no token needed. ────────────────
-- Everything someone needs to decide whether to join, before they've agreed to
-- anything: what the ride is, when it starts, where it goes, who's already in.
-- Includes the ROUTE, because joining must download it to the phone — PackRide is
-- a navigation tool and navigation has to work in a valley with no signal.

create or replace function event_info(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  e   events%rowtype;
  rt  routes%rowtype;
  res jsonb;
begin
  select * into e from events where code = upper(p_code);
  if e.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  if e.route_id is not null then
    select * into rt from routes where id = e.route_id;
  end if;

  select jsonb_build_object(
    'code',       e.code,
    'name',       e.name,
    'startAt',    e.start_at,
    'preset',     e.preset,
    'intervalS',  e.interval_s,
    'organiser',  (select s.label from shares s where s.id = e.organiser_id),
    'members',    (select count(*) from event_members m where m.event_id = e.id),
    'route', case when rt.id is null then null else jsonb_build_object(
      'key',       rt.route_key,
      'name',      rt.name,
      'poly',      rt.poly,
      'totalDist', rt.total_dist,
      'stops',     coalesce(rt.stops, '[]'::jsonb)
    ) end
  ) into res;

  return res;
end $$;

-- ── event_join ────────────────────────────────────────────────────────────
-- Idempotent: joining twice just updates your display name.

create or replace function event_join(
  p_write_token  text,
  p_code         text,
  p_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  eid uuid;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  select id into eid from events where code = upper(p_code);
  if eid is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  insert into event_members (event_id, share_id, display_name)
  values (eid, sid, nullif(p_display_name, ''))
  on conflict (event_id, share_id) do update
    set display_name = coalesce(excluded.display_name, event_members.display_name);

  return event_info(upper(p_code));
end $$;

-- ── event_pack — THE ONE. Where is everybody? ─────────────────────────────
-- Public (code only). Riders poll it to see the pack; spectators poll it to watch.
-- Returns every member's latest fix plus a short recent trail, sorted by distance
-- along the route — which IS the leaderboard, for free.
--
-- `you` is echoed back so a rider can tell which dot is theirs without the server
-- ever having to know who is asking. Optional; omit it and you get the pack.

create or replace function event_pack(
  p_code        text,
  p_write_token text default null,
  p_trail       int  default 60
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  e    events%rowtype;
  me   uuid;
  res  jsonb;
begin
  select * into e from events where code = upper(p_code);
  if e.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  if p_write_token is not null then
    select id into me from shares where write_token = p_write_token;
  end if;

  select jsonb_build_object(
    'code',      e.code,
    'name',      e.name,
    'startAt',   e.start_at,
    'intervalS', e.interval_s,
    'riders', coalesce((
      select jsonb_agg(r order by (r->>'distKm')::real desc nulls last)
      from (
        select jsonb_build_object(
          'name',     coalesce(m.display_name, s.label, 'Rider'),
          'isYou',    (me is not null and m.share_id = me),
          'lastSeen', lp.t,
          'lat',      lp.lat,
          'lon',      lp.lon,
          'speed',    lp.speed,
          'distKm',   lp.dist_km,
          'trail',    coalesce(tr.pts, '[]'::jsonb)
        ) as r
        from event_members m
        join shares s on s.id = m.share_id
        -- the ride this member is running IN THIS EVENT
        left join lateral (
          select rd.ride_id from rides rd
           where rd.share_id = m.share_id and rd.event_id = e.id
           order by rd.started_at desc limit 1
        ) rr on true
        -- their latest fix on it
        left join lateral (
          select p.lat, p.lon, p.t, p.speed, p.dist_km
            from positions p
           where p.share_id = m.share_id and p.ride_id = rr.ride_id
           order by p.t desc limit 1
        ) lp on true
        -- and a short recent trail, so the pack map shows movement not just dots
        left join lateral (
          select jsonb_agg(jsonb_build_array(q.lat, q.lon) order by q.t) as pts
            from (
              select p.lat, p.lon, p.t
                from positions p
               where p.share_id = m.share_id and p.ride_id = rr.ride_id
               order by p.t desc
               limit greatest(2, least(p_trail, 500))
            ) q
        ) tr on true
        where lp.t is not null           -- only riders who have actually started
      ) x
    ), '[]'::jsonb)
  ) into res;

  return res;
end $$;

-- ── ride_start (v5) — now takes an event code ─────────────────────────────
-- Replaces the v3 version. p_event_code null = a solo ride, exactly as before.

drop function if exists ride_start(text, text, text);

create or replace function ride_start(
  p_write_token text,
  p_ride_id     text,
  p_route_key   text default null,
  p_event_code  text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  rid uuid;
  eid uuid;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  if p_route_key is not null then
    select id into rid from routes
     where share_id = sid and route_key = p_route_key;
  end if;

  if p_event_code is not null then
    select id into eid from events where code = upper(p_event_code);
  end if;

  insert into rides (share_id, ride_id, route_id, event_id)
  values (sid, p_ride_id, rid, eid)
  on conflict (share_id, ride_id) do update
    set route_id = coalesce(excluded.route_id, rides.route_id),
        event_id = coalesce(excluded.event_id, rides.event_id);
end $$;

-- ── event_list — the events I'm in ────────────────────────────────────────

create or replace function event_list(p_write_token text)
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
           'code',      e.code,
           'name',      e.name,
           'startAt',   e.start_at,
           'preset',    e.preset,
           'intervalS', e.interval_s,
           'organiser', m.is_organiser,
           'members',   (select count(*) from event_members m2 where m2.event_id = e.id)
         ) order by e.start_at desc nulls last, e.created_at desc), '[]'::jsonb)
    into res
    from event_members m
    join events e on e.id = m.event_id
   where m.share_id = sid;

  return res;
end $$;

-- ── event_leave ───────────────────────────────────────────────────────────

create or replace function event_leave(p_write_token text, p_code text)
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

  delete from event_members
   where share_id = sid
     and event_id = (select id from events where code = upper(p_code));
end $$;

-- ── Permissions ───────────────────────────────────────────────────────────

grant execute on function event_create(text, text, text, timestamptz, text, int) to anon, authenticated;
grant execute on function event_info(text)                                       to anon, authenticated;
grant execute on function event_join(text, text, text)                           to anon, authenticated;
grant execute on function event_pack(text, text, int)                            to anon, authenticated;
grant execute on function event_list(text)                                       to anon, authenticated;
grant execute on function event_leave(text, text)                                to anon, authenticated;
grant execute on function ride_start(text, text, text, text)                     to anon, authenticated;
