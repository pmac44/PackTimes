-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — routes carry ELEVATION, schema v8  (14 July 2026)
--  ADDITIVE. Run AFTER schema-v7.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  THE BUG (Peter found it in the PackRide sim): a joined rider got the route as
--  an encoded polyline — lat/lon ONLY — and the phone filled in ele:0 for every
--  point. No elevation graph, and worse: the joined rider's pace model saw a
--  FLAT route, so their ETAs were optimistic on any hilly ride.
--
--  THE FIX: routes now carry an `ele` column — elevations in whole metres,
--  delta-encoded with the same varint scheme as the polyline (~1–2 bytes a
--  point; a 6,000-point route is ~6 KB). The client encodes on upload
--  (route_ensure) and decodes on join (event_info → eventRouteToRoute).
--
--  ORDER MATTERS: run this BEFORE deploying app v256 — the new client calls
--  route_ensure with p_ele, which the v7 function doesn't accept. Old clients
--  keep working against the new function (p_ele defaults to null).
--
--  share_view (PackView) is deliberately NOT touched: the spectator page draws
--  no elevation graph and computes no ETAs. Add it there if that ever changes.
-- ═══════════════════════════════════════════════════════════════════════════

alter table routes add column if not exists ele text;

-- route_ensure gains p_ele. Drop the old signature first — two overloads would be
-- ambiguous to PostgREST's named-argument matching.
drop function if exists route_ensure(text, text, text, text, real, jsonb);

create or replace function route_ensure(
  p_write_token text,
  p_route_key   text,
  p_name        text,
  p_poly        text,
  p_total_dist  real,
  p_stops       jsonb default null,
  p_ele         text  default null
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

  insert into routes (share_id, route_key, name, poly, total_dist, stops, ele)
  values (sid, p_route_key, nullif(p_name,''), p_poly, p_total_dist, p_stops, p_ele)
  on conflict (share_id, route_key) do update
    set name = excluded.name,
        poly = excluded.poly,
        total_dist = excluded.total_dist,
        stops = excluded.stops,
        ele = excluded.ele,
        updated_at = now()
  returning id into rid;

  return rid;
end $$;

grant execute on function route_ensure(text, text, text, text, real, jsonb, text) to anon, authenticated;

-- event_info now hands the elevation to the joining phone. Same signature, so
-- existing grants persist; a route uploaded before v8 simply has ele = null and
-- the client falls back to 0 exactly as before.
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
      'ele',       rt.ele,
      'totalDist', rt.total_dist,
      'stops',     coalesce(rt.stops, '[]'::jsonb)
    ) end
  ) into res;

  return res;
end $$;
