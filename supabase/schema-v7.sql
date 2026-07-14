-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — route-aware interpolation, schema v7  (13 July 2026)
--  ADDITIVE. Replaces one function. Run AFTER schema-v6.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  ONE CHANGE: event_pack's trail points now carry dist_km — the rider's distance
--  ALONG THE ROUTE — as well as lat/lon/time.
--
--  WHY: the client interpolates between fixes to make a 30-second cadence look
--  live (§3.8). Interpolating in a straight LINE cuts corners — the dot leaves the
--  road and swims across the paddock between two points 250 m apart. But every
--  position already knows how far along the route it is, so the client can instead
--  interpolate ALONG THE ROUTE — walk the road between the two fixes — and the dot
--  follows the actual line. It just needed the number to be sent.
--
--  Costs 4 bytes a point. PackView's share_view already carried dist_km.
--
--  Trail point shape is now: [lat, lon, epoch_ms, dist_km]
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists event_pack(text, text, timestamptz, int);

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
          -- [lat, lon, epoch_ms, dist_km] — dist_km is what lets the client walk the
          -- ROUTE between two fixes instead of cutting straight across.
          select jsonb_agg(
                   jsonb_build_array(
                     q.lat, q.lon,
                     (extract(epoch from q.t) * 1000)::bigint,
                     q.dist_km
                   ) order by q.t
                 ) as pts
            from (
              select p.lat, p.lon, p.t, p.dist_km
                from positions p
               where p.share_id = m.share_id
                 and p.ride_id  = rr.ride_id
                 and (p_since is null or p.t > p_since)
               order by p.t desc
               limit greatest(1, least(p_trail, 2000))
            ) q
        ) tr on true
        where lp.t is not null
      ) x
    ), '[]'::jsonb)
  ) into res;

  return res;
end $$;

grant execute on function event_pack(text, text, timestamptz, int) to anon, authenticated;
