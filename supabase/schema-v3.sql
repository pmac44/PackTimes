-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — location sharing, schema v3  (13 July 2026)
--  ADDITIVE. Drops nothing. Existing shares, links and positions all survive.
--  Run AFTER schema-v2.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  WHAT THIS ADDS: the ROUTE. Until now PackView knew where a rider had BEEN.
--  It had no idea there was a plan.
--
--  WHY IT MATTERS (Peter, and this is the strongest reason on the list): in an
--  emergency, knowing someone's PLAN can be more use than knowing their last
--  position — a plan is searchable even when a position is hours stale or was
--  never sent at all. The route is the plan.
--
--  THE SHAPE:
--    routes — one row per route the rider has ever shared. Uploaded ONCE (the
--             app upserts on route_key, so riding the same route again costs
--             nothing new). Owned by the share, so deleting the share takes the
--             routes with it. Geometry is an ENCODED POLYLINE — the standard
--             Google algorithm, ~5 bytes a point. A 6,000-point / 300 km route
--             is about 35 KB, versus ~150 KB as raw JSON.
--    rides  — "ride abc123 followed route xyz". One row per ride. This is what
--             lets a PINNED link show the right route for its one ride, and a
--             permanent link follow the rider onto whatever they ride next.
--
--  PRIVACY NOTE. The route reveals where you are GOING, not just where you have
--  been — your overnight stop, the fact you'll be at that junction in two hours.
--  That is deliberate and it is the point of the feature. It is also more than a
--  watcher had before, so it is written down here rather than discovered later.
--  Peter's reasoning for defaulting it ON: family should have it; a group ride
--  already has the route; a public event publishes it anyway. If a "position
--  only, no route" link is ever wanted, add a `show_route` flag to view_links —
--  the plumbing below already isolates it cleanly.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Tables ────────────────────────────────────────────────────────────────

create table if not exists routes (
  id          uuid primary key default gen_random_uuid(),
  share_id    uuid not null references shares(id) on delete cascade,
  route_key   text not null,            -- the PackTimes route.id, as held on the phone
  name        text,
  poly        text not null,            -- encoded polyline, precision 5
  total_dist  real,
  stops       jsonb,                    -- [{name,type,dist,lat,lon}] — drawn by the same drawMap
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  unique (share_id, route_key)
);

create table if not exists rides (
  share_id    uuid not null references shares(id) on delete cascade,
  ride_id     text not null,            -- the recording's id
  route_id    uuid references routes(id) on delete set null,
  started_at  timestamptz not null default now(),
  primary key (share_id, ride_id)
);

alter table routes enable row level security;
alter table rides  enable row level security;
-- No policies, as with every other table. The public key cannot touch them.

-- ── route_ensure — upload a route, or confirm it's already up ─────────────
-- The app calls this once at the start of a ride. Upserting on (share_id,
-- route_key) means re-riding a route is free, and EDITING a route (new stops,
-- new geometry) quietly republishes it. Returns the route's id.

create or replace function route_ensure(
  p_write_token text,
  p_route_key   text,
  p_name        text,
  p_poly        text,
  p_total_dist  real,
  p_stops       jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  rid uuid;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  insert into routes (share_id, route_key, name, poly, total_dist, stops)
  values (sid, p_route_key, nullif(p_name,''), p_poly, p_total_dist, p_stops)
  on conflict (share_id, route_key) do update
    set name = excluded.name,
        poly = excluded.poly,
        total_dist = excluded.total_dist,
        stops = excluded.stops,
        updated_at = now()
  returning id into rid;

  return rid;
end $$;

-- ── ride_start — "this ride is following that route" ──────────────────────
-- p_route_key null → a free ride with no route. Perfectly valid; PackView then
-- just shows the breadcrumb trail, as it did before v3.

create or replace function ride_start(
  p_write_token text,
  p_ride_id     text,
  p_route_key   text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  sid uuid;
  rid uuid;
begin
  select id into sid from shares where write_token = p_write_token;
  if sid is null then
    raise exception 'invalid share';
  end if;

  if p_route_key is not null then
    select id into rid from routes
     where share_id = sid and route_key = p_route_key;
  end if;

  insert into rides (share_id, ride_id, route_id)
  values (sid, p_ride_id, rid)
  on conflict (share_id, ride_id) do update
    set route_id = coalesce(excluded.route_id, rides.route_id);
end $$;

-- ── share_view — now hands back the route as well as the trail ────────────
-- Replaces the v2 version. Everything else about it is unchanged.

drop function if exists share_view(text, int);

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
  l    view_links%rowtype;
  s    shares%rowtype;
  rid  text;
  rt   routes%rowtype;
  res  jsonb;
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

  -- The route this ride is following, if any.
  if rid is not null then
    select r.* into rt
      from rides rd
      join routes r on r.id = rd.route_id
     where rd.share_id = s.id and rd.ride_id = rid;
  end if;

  select jsonb_build_object(
    'label',      s.label,
    'linkName',   l.name,
    'rideId',     rid,
    'lastSeenAt', (select max(p.t) from positions p
                    where p.share_id = s.id
                      and p.ride_id is not distinct from rid),
    'expiresAt',  l.expires_at,
    'route', case when rt.id is null then null else jsonb_build_object(
      'name',      rt.name,
      'poly',      rt.poly,
      'totalDist', rt.total_dist,
      'stops',     coalesce(rt.stops, '[]'::jsonb)
    ) end,
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

grant execute on function route_ensure(text, text, text, text, real, jsonb) to anon, authenticated;
grant execute on function ride_start(text, text, text)                      to anon, authenticated;
grant execute on function share_view(text, int)                             to anon, authenticated;
