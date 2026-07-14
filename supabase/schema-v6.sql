-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — delta polling, schema v6  (13 July 2026)
--  ADDITIVE. Drops no tables. Replaces two functions. Run AFTER schema-v5.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  THE PROBLEM THIS FIXES — and it's the one that decides whether this is free to
--  run or expensive to run.
--
--  Cost does NOT scale with riders. It scales with WATCHERS. And v2–v5 were
--  extravagant about them:
--
--    · share_view returned the rider's ENTIRE trail (~1,000 points ≈ 30 KB) on
--      every poll, every 30 seconds. The watcher already had all but the last two
--      points of it.
--    · It ALSO re-sent the ROUTE POLYLINE (~24 KB) every poll — a route that had
--      not changed in three days.
--    · event_pack was worse: EVERY rider's trail, to EVERY rider, every 15 s.
--      That is O(riders²) bandwidth, on a phone, on mobile data.
--
--  The arithmetic: 54 KB × 2 polls/min × 20 h = ~130 MB PER WATCHER, PER RIDE.
--  The free tier's 5 GB/month is therefore about 40 watcher-rides. One
--  moderately-watched event would blow it — not because of the riders, but
--  because ten people left the page open.
--
--  THE FIX: send only what the client doesn't have.
--    · p_since     — "I have everything up to this timestamp." Returns the two or
--                    three points that appeared since. A poll drops from ~30 KB to
--                    ~100 bytes.
--    · p_have_route— "I already hold the route with this key." The route is then
--                    omitted entirely, and `routeCached:true` says so.
--
--  Result: ~130 MB per watcher-ride becomes well under 1 MB. Roughly 300×.
--
--  The FIRST load is still a full fetch, and that is fine — it always was. A
--  watcher coming back after three days pays one 30 KB download and then goes back
--  to deltas. The waste was never the size; it was sending it 2,400 times.
--
--  KEEP THIS PROPERTY. Any future field added to these responses should ask: does
--  the client already have this? If yes, don't send it.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── share_view (v6) — PackView ────────────────────────────────────────────
-- p_since      null → full trail (first load, or a fresh return after days away)
--              set  → only points newer than this
-- p_have_route null → send the route
--              set  → send it ONLY if the key differs (i.e. the rider changed route)

drop function if exists share_view(text, int);

create or replace function share_view(
  p_view_code  text,
  p_since      timestamptz default null,
  p_have_route text        default null,
  p_trail      int         default 2000
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  l        view_links%rowtype;
  s        shares%rowtype;
  rid      text;
  rt       routes%rowtype;
  sendrt   boolean := false;
  res      jsonb;
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

  if rid is not null then
    select r.* into rt
      from rides rd
      join routes r on r.id = rd.route_id
     where rd.share_id = s.id and rd.ride_id = rid;
  end if;

  -- Only send the route if they haven't got it (or have a different one).
  sendrt := rt.id is not null and (p_have_route is null or p_have_route <> rt.route_key);

  select jsonb_build_object(
    'label',       s.label,
    'linkName',    l.name,
    'rideId',      rid,
    'lastSeenAt',  (select max(p.t) from positions p
                     where p.share_id = s.id
                       and p.ride_id is not distinct from rid),
    'expiresAt',   l.expires_at,
    'since',       p_since,                -- echoed back so the client can't get confused
    'routeKey',    rt.route_key,
    'routeCached', (rt.id is not null and not sendrt),
    'route', case when not sendrt then null else jsonb_build_object(
      'key',       rt.route_key,
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
             and (p_since is null or t > p_since)
           order by t desc
           limit greatest(1, least(p_trail, 5000))
        ) p
    ), '[]'::jsonb)
  ) into res;

  return res;
end $$;

-- ── event_pack (v6) — PackRide ────────────────────────────────────────────
-- Same deal, and it matters far more here: without p_since this was every rider's
-- trail, to every rider, every 15 seconds — O(riders²) bandwidth over mobile data.
--
-- Each rider gets a stable short `id` so the client can accumulate their trail
-- across polls without the server ever having to re-send it. Derived from the
-- share id, so it's stable but reveals nothing.

drop function if exists event_pack(text, text, int);

create or replace function event_pack(
  p_code        text,
  p_write_token text        default null,
  p_since       timestamptz default null,
  p_trail       int         default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  e   events%rowtype;
  me  uuid;
  res jsonb;
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
    'since',     p_since,
    'riders', coalesce((
      select jsonb_agg(r order by (r->>'distKm')::real desc nulls last)
      from (
        select jsonb_build_object(
          'id',       left(md5(m.share_id::text), 8),
          'name',     coalesce(m.display_name, s.label, 'Rider'),
          'isYou',    (me is not null and m.share_id = me),
          'lastSeen', lp.t,
          'lat',      lp.lat,
          'lon',      lp.lon,
          'speed',    lp.speed,
          'distKm',   lp.dist_km,
          -- ONLY the points this client hasn't seen. On a steady poll that's one
          -- or two per rider, not a whole trail each.
          'trail',    coalesce(tr.pts, '[]'::jsonb)
        ) as r
        from event_members m
        join shares s on s.id = m.share_id
        left join lateral (
          select rd.ride_id from rides rd
           where rd.share_id = m.share_id and rd.event_id = e.id
           order by rd.started_at desc limit 1
        ) rr on true
        left join lateral (
          select p.lat, p.lon, p.t, p.speed, p.dist_km
            from positions p
           where p.share_id = m.share_id and p.ride_id = rr.ride_id
           order by p.t desc limit 1
        ) lp on true
        left join lateral (
          select jsonb_agg(jsonb_build_array(q.lat, q.lon, (extract(epoch from q.t)*1000)::bigint) order by q.t) as pts
            from (
              select p.lat, p.lon, p.t
                from positions p
               where p.share_id = m.share_id
                 and p.ride_id  = rr.ride_id
                 and (p_since is null or p.t > p_since)
               order by p.t desc
               limit greatest(1, least(p_trail, 2000))
            ) q
        ) tr on true
        where lp.t is not null           -- only riders who have actually started
      ) x
    ), '[]'::jsonb)
  ) into res;

  return res;
end $$;

-- ── Permissions ───────────────────────────────────────────────────────────

grant execute on function share_view(text, timestamptz, text, int)        to anon, authenticated;
grant execute on function event_pack(text, text, timestamptz, int)        to anon, authenticated;
