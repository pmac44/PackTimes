-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — location sharing, schema v4  (13 July 2026)
--  ADDITIVE. Drops no tables. Run AFTER schema-v3.sql.
-- ═══════════════════════════════════════════════════════════════════════════
--
--  WHAT THIS ADDS: the rider's control over their own data. Nothing else.
--
--  THE RETENTION POLICY, in one line (Peter's wording, 13 Jul 2026):
--
--      "All rides stay on the server unless you delete them,
--       which you can do at any time."
--
--  That's the whole rule. These functions are how a rider does it.
--
--  DO NOT ADD AN EXPIRY JOB. The original plan auto-deleted after ~7 days. It was
--  wrong on two counts:
--
--  1. IT WAS DANGEROUS. A rider who lives alone goes missing on Tuesday; nobody is
--     worried until Friday; and the single most useful fact in the world — their
--     last known position — has been deleted by us, on schedule, for their own
--     good. If cost ever forces a cleanup job, it must never touch the rider's
--     most recent ride.
--
--  2. THE HISTORY IS THE POINT. Peter looks back at his own races from years ago on
--     dot-watcher pages and replays them. That is a real feature, not clutter.
--
--  A RIDER deleting their own data is a different thing entirely, and is always
--  allowed — including their most recent ride. They are conscious and in reception,
--  by definition; that is not the failure mode we are guarding against.
--
--  THE HONEST TRADE-OFF, written down so nobody has to rediscover it: "we delete
--  it" is a stronger privacy promise than "we keep it but nobody can see it". Kept
--  data can be breached or exposed by a future bug; deleted data cannot. What makes
--  retention defensible here is that KEEPING is not SHOWING — a permanent view link
--  only ever reads the rider's CURRENT ride and cannot reach backwards. An old ride
--  is invisible to everyone on earth unless the rider deliberately mints a link
--  pointed at it. Retention is between the rider and the server, not the rider and
--  the world. If that ever stops being true, this policy has to be reopened.
--
--  REPLAY, for free: a link with ride_id SET and expires_at NULL is a permanent
--  dot-watcher page for that one ride, forever, that can never show anything else.
--  That is the 2024-race-replay feature, and the v2 schema already supported it.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── ride_list — what's on the server, so the rider can see it before deleting ──

create or replace function ride_list(p_write_token text)
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

  select coalesce(jsonb_agg(x order by x.started_at desc), '[]'::jsonb) into res
  from (
    select rd.ride_id,
           rd.started_at,
           rt.name as route_name,
           (select count(*) from positions p
             where p.share_id = sid and p.ride_id = rd.ride_id) as points,
           (select max(p.t) from positions p
             where p.share_id = sid and p.ride_id = rd.ride_id) as last_seen
      from rides rd
      left join routes rt on rt.id = rd.route_id
     where rd.share_id = sid
  ) x;

  return res;
end $$;

-- ── ride_delete — remove ONE ride's positions ─────────────────────────────
-- Also revokes any view link pinned to it: a link pointing at a ride whose data
-- is gone is a dead link, and leaving it live would be a lie.
-- Deliberately DOES let the rider delete their most recent ride — it's their data.

create or replace function ride_delete(p_write_token text, p_ride_id text)
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

  delete from positions where share_id = sid and ride_id = p_ride_id;

  update view_links set revoked_at = now()
   where share_id = sid and ride_id = p_ride_id and revoked_at is null;

  delete from rides where share_id = sid and ride_id = p_ride_id;
end $$;

-- ── share_purge — wipe everything, keep the identity ──────────────────────
-- Every position, every ride, every route. The share and its links survive, so the
-- rider doesn't have to re-issue links to their family. A clean slate, not a
-- resignation.

create or replace function share_purge(p_write_token text)
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

  delete from positions where share_id = sid;
  delete from rides     where share_id = sid;
  delete from routes    where share_id = sid;

  update view_links set revoked_at = now()
   where share_id = sid and ride_id is not null and revoked_at is null;
end $$;

-- ── share_destroy — the nuclear option ────────────────────────────────────
-- Deletes the share itself. Every link dies, every position, ride and route goes
-- with it (ON DELETE CASCADE). The rider's token becomes worthless. Nothing of
-- them remains on the server. This must always exist and must always work — it is
-- the promise that makes the rest of the promises credible.

create or replace function share_destroy(p_write_token text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from shares where write_token = p_write_token;
end $$;

-- ── Permissions ───────────────────────────────────────────────────────────

grant execute on function ride_list(text)          to anon, authenticated;
grant execute on function ride_delete(text, text)  to anon, authenticated;
grant execute on function share_purge(text)        to anon, authenticated;
grant execute on function share_destroy(text)      to anon, authenticated;
