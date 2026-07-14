-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — location sharing, schema v2 patch  (13 July 2026)
-- ═══════════════════════════════════════════════════════════════════════════
--
--  WHY: v1 made one share (and therefore one view link) per ride. That would
--  mean sending your wife a fresh URL every single ride — useless.
--
--  v2: ONE PERMANENT LINK PER RIDER. You create it once, hand it over once,
--  and it works forever. Each ride is tagged with a `ride_id`, and PackView
--  only ever shows the trail of the LATEST ride. The link dies only if you
--  deliberately revoke it (share_end).
--
--  "Am I riding right now?" is answered by last_seen_at, not by a flag — if a
--  position landed in the last few minutes, they're moving. If the last one was
--  six hours ago, they're not. The viewer decides how to phrase that.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Positions get a ride_id ────────────────────────────────────────────

alter table positions add column if not exists ride_id text;
create index if not exists positions_share_ride_t on positions (share_id, ride_id, t desc);

-- ── 2. share_push now tags the ride ───────────────────────────────────────

drop function if exists share_push(text, double precision, double precision, real, real, real, timestamptz);

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
  select id into sid
    from shares
   where write_token = p_write_token
     and ended_at is null;

  if sid is null then
    raise exception 'invalid or revoked share';
  end if;

  insert into positions (share_id, ride_id, lat, lon, ele, speed, dist_km, t)
  values (sid, nullif(p_ride_id, ''), p_lat, p_lon, p_ele, p_speed, p_dist_km,
          coalesce(p_t, now()));

  update shares set last_seen_at = now() where id = sid;
end $$;

-- ── 3. share_view returns only the CURRENT ride's trail ───────────────────

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
  s    shares%rowtype;
  rid  text;
  res  jsonb;
begin
  select * into s from shares where view_code = upper(p_view_code);

  if s.id is null or s.ended_at is not null then
    return jsonb_build_object('error', 'not_found');
  end if;

  -- the ride_id of the most recent position = the ride they're on now
  select p.ride_id into rid
    from positions p
   where p.share_id = s.id
   order by p.t desc
   limit 1;

  select jsonb_build_object(
    'label',      s.label,
    'routeId',    s.route_id,
    'rideId',     rid,
    'startedAt',  s.created_at,
    'lastSeenAt', s.last_seen_at,
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

-- ── 4. Permissions (new signatures need re-granting) ──────────────────────

grant execute on function share_push(text, text, double precision, double precision, real, real, real, timestamptz) to anon, authenticated;
grant execute on function share_view(text, int) to anon, authenticated;
