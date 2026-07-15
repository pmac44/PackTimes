-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — routes carry the PACE SETTINGS, schema v9  (16 July 2026)
--  ADDITIVE. Run AFTER schema-v8.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  THE BUG: a joined rider got the organiser's route, stops and start time — but
--  their phone rebuilt the plan with newRoute()'s GENERIC DEFAULTS for pace:
--  timeFactor 1.0, riderPreset 'regular', loadPreset 'moderate', no paceSegs.
--  So the ETAs a joiner saw were neither the organiser's plan NOR the joiner's
--  own speed: they were a stranger's. On a loaded bikepacking route the load
--  preset alone is worth ~8–10% — hours, over a multi-day ride.
--
--  THE FIX: routes gain a `pace` jsonb column carrying exactly what the existing
--  "share whole ride" file has always carried (see SHARE WHOLE RIDE in
--  index.html): timeFactor, riderPreset, loadPreset, paceSegs. PackRide was the
--  odd one out — two ways of sharing the same plan that disagreed.
--
--  WHY THIS IS NOT "COPYING SOMEONE ELSE'S SPEED ONTO YOU" (Peter's rule):
--    · the ORGANISER decides the group's pace — that IS the plan, and on a group
--      ride everyone should be reading the same one;
--    · a joiner running Advanced calibration automatically substitutes their OWN
--      rider ability — buildCumRiding line ~1739 gives UI.estModeAdv priority
--      over the route's riderPreset, so nothing is overwritten and there is no
--      double-count;
--    · GPS + adaptive speed correct whatever is left, on the day;
--    · and the joiner can just change it, like any other route setting.
--  Reconciling per-rider speeds automatically is the rabbit warren. This isn't
--  that — it's shipping the plan the organiser actually made.
--
--  ORDER MATTERS: run this BEFORE deploying the client that sends p_pace — the
--  new client calls route_ensure with p_pace, which the v8 function does not
--  accept. Old clients keep working against the new function (p_pace defaults to
--  null, and a route with pace = null makes the joiner fall back to today's
--  behaviour exactly).
--
--  Existing events keep their old route row. route_ensure upserts on
--  (share_id, route_key), so re-creating the event — or the organiser simply
--  riding it again — republishes the route with its pace attached.
--
--  share_view (PackView) is deliberately NOT touched: the spectator page computes
--  no ETAs. Add it there if that ever changes.
-- ═══════════════════════════════════════════════════════════════════════════

alter table routes add column if not exists pace jsonb;

-- route_ensure gains p_pace. Drop the old signature first — two overloads would be
-- ambiguous to PostgREST's named-argument matching.
drop function if exists route_ensure(text, text, text, text, real, jsonb, text);

create or replace function route_ensure(
  p_write_token text,
  p_route_key   text,
  p_name        text,
  p_poly        text,
  p_total_dist  real,
  p_stops       jsonb default null,
  p_ele         text  default null,
  p_pace        jsonb default null
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

  insert into routes (share_id, route_key, name, poly, total_dist, stops, ele, pace)
  values (sid, p_route_key, nullif(p_name,''), p_poly, p_total_dist, p_stops, p_ele, p_pace)
  on conflict (share_id, route_key) do update
    set name = excluded.name,
        poly = excluded.poly,
        total_dist = excluded.total_dist,
        stops = excluded.stops,
        ele = excluded.ele,
        pace = excluded.pace,
        updated_at = now()
  returning id into rid;

  return rid;
end $$;

grant execute on function route_ensure(text, text, text, text, real, jsonb, text, jsonb) to anon, authenticated;

-- event_info hands the pace settings to the joining phone. Same signature, so
-- existing grants persist; a route uploaded before v9 simply has pace = null and
-- the client keeps its own defaults, exactly as before.
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
      'stops',     coalesce(rt.stops, '[]'::jsonb),
      'pace',      rt.pace
    ) end
  ) into res;

  return res;
end $$;
