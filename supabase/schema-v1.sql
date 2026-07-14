-- ═══════════════════════════════════════════════════════════════════════════
--  PackTimes — location sharing, schema v1  (13 July 2026)
-- ═══════════════════════════════════════════════════════════════════════════
--
--  THE SECURITY MODEL, in plain English:
--
--  The publishable key sits in index.html, which is public on GitHub. So we
--  must assume ANYONE has it. Therefore the two tables below are locked shut —
--  Row Level Security is ON and there are NO policies, which means the public
--  key cannot read or write them directly. At all.
--
--  Everything happens through the four functions at the bottom instead. They
--  run as the owner (`security definer`), so they can reach the tables, and
--  each one does exactly one narrow job:
--
--    share_create()  → makes a share. Returns TWO codes:
--                        view_code    (8 chars, PUBLIC — goes in the link you
--                                      give your wife)
--                        write_token  (48 hex chars, SECRET — lives only on
--                                      your phone; it is what proves a position
--                                      push is really from you)
--    share_push()    → needs the write_token. Adds one position. Nothing else.
--    share_end()     → needs the write_token. Closes the share.
--    share_view()    → needs only the view_code. Returns label + trail.
--                      It CANNOT return the write_token — there's no path.
--
--  So: holding the view link lets you WATCH. It does not let you write, and it
--  does not let you find anyone else's ride. Guessing a view_code is 32^8 ≈
--  1.1 trillion tries.
--
--  Known, accepted limit: anyone with the publishable key can call
--  share_create() and make junk shares. Costs us nothing but rows. If it ever
--  matters, we rate-limit it. Not worth solving today.
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ── Tables ────────────────────────────────────────────────────────────────

create table if not exists shares (
  id            uuid primary key default gen_random_uuid(),
  view_code     text unique not null,     -- public, in the link
  write_token   text unique not null,     -- secret, phone only
  label         text,                     -- "Peter" — what the viewer sees
  route_id      text,                     -- PackTimes route id, if any
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz,              -- when the last position landed
  ended_at      timestamptz               -- null while live
);

create table if not exists positions (
  id          bigserial primary key,
  share_id    uuid not null references shares(id) on delete cascade,
  lat         double precision not null,
  lon         double precision not null,
  ele         real,
  speed       real,                       -- km/h
  dist_km     real,                       -- distance along route, if following one
  t           timestamptz not null,       -- time of the GPS fix (device clock)
  created_at  timestamptz not null default now()
);

create index if not exists positions_share_t on positions (share_id, t desc);

-- Lock both tables. RLS on, zero policies = the public key cannot touch them.
alter table shares    enable row level security;
alter table positions enable row level security;

-- ── Helper: short human-safe code ─────────────────────────────────────────
-- 32-char alphabet, no 0/O/1/I (misread on a phone screen). Uses the crypto
-- RNG, not random(), so codes aren't predictable.

-- NOTE: `search_path = public, extensions` — pgcrypto lives in the `extensions`
-- schema on Supabase, not public. Without it: "gen_random_bytes does not exist".

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

-- ── share_create ──────────────────────────────────────────────────────────

create or replace function share_create(
  p_label    text default null,
  p_route_id text default null
)
returns table (view_code text, write_token text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v text;
  w text;
begin
  loop
    v := pt_code(8);
    exit when not exists (select 1 from shares s where s.view_code = v);
  end loop;

  w := encode(gen_random_bytes(24), 'hex');

  insert into shares (view_code, write_token, label, route_id)
  values (v, w, nullif(p_label, ''), nullif(p_route_id, ''));

  return query select v, w;
end $$;

-- ── share_push ────────────────────────────────────────────────────────────

create or replace function share_push(
  p_write_token text,
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
set search_path = public
as $$
declare
  sid uuid;
begin
  select id into sid
    from shares
   where write_token = p_write_token
     and ended_at is null;

  if sid is null then
    raise exception 'invalid or ended share';
  end if;

  insert into positions (share_id, lat, lon, ele, speed, dist_km, t)
  values (sid, p_lat, p_lon, p_ele, p_speed, p_dist_km, coalesce(p_t, now()));

  update shares set last_seen_at = now() where id = sid;
end $$;

-- ── share_end ─────────────────────────────────────────────────────────────

create or replace function share_end(p_write_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update shares
     set ended_at = now()
   where write_token = p_write_token
     and ended_at is null;
end $$;

-- ── share_view ────────────────────────────────────────────────────────────
-- The ONLY thing PackView calls. Returns the label, the timestamps, and the
-- breadcrumb trail. Trail points are packed as arrays to keep the payload
-- small: [lat, lon, epoch_ms, speed, dist_km].

create or replace function share_view(
  p_view_code text,
  p_trail     int default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s   shares%rowtype;
  res jsonb;
begin
  select * into s from shares where view_code = upper(p_view_code);

  if s.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  select jsonb_build_object(
    'label',      s.label,
    'routeId',    s.route_id,
    'startedAt',  s.created_at,
    'lastSeenAt', s.last_seen_at,
    'endedAt',    s.ended_at,
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
           order by t desc
           limit greatest(1, least(p_trail, 2000))
        ) p
    ), '[]'::jsonb)
  ) into res;

  return res;
end $$;

-- ── Permissions ───────────────────────────────────────────────────────────
-- `anon` is the role the publishable key maps to. It may call these four
-- functions and nothing else. It cannot call pt_code, and it cannot see the
-- tables.

revoke execute on function pt_code(int) from public, anon;

grant execute on function share_create(text, text)                 to anon, authenticated;
grant execute on function share_push(text, double precision, double precision, real, real, real, timestamptz) to anon, authenticated;
grant execute on function share_end(text)                          to anon, authenticated;
grant execute on function share_view(text, int)                    to anon, authenticated;
