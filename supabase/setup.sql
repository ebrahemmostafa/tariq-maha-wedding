-- Tariq & Maha wedding — RSVP storage
-- Run once in your Supabase project: Dashboard → SQL Editor → New query → paste → Run.
-- Replace __ADMIN_PASSCODE__ (near the bottom) with the passcode for admin.html before running.
-- The passcode is stored only as a bcrypt hash; run the last statement again to change it.

create extension if not exists pgcrypto with schema extensions;

-- If an `rsvps` table with a different layout already exists, keep it as `rsvps_old`
-- (nothing is deleted) and create the expected table below.
do $$
begin
  if to_regclass('public.rsvps') is not null
     and not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'rsvps' and column_name = 'responded_at') then
    if to_regclass('public.rsvps_old') is not null then
      raise exception 'public.rsvps has an unexpected layout and public.rsvps_old already exists; rename or drop one of them first';
    end if;
    alter table public.rsvps rename to rsvps_old;
    raise notice 'Existing public.rsvps renamed to public.rsvps_old';
  end if;
end $$;

-- The old table keeps whatever access it had; make it private (dashboard / SQL Editor only).
do $$
declare
  p record;
begin
  if to_regclass('public.rsvps_old') is not null then
    alter table public.rsvps_old enable row level security;
    revoke all on public.rsvps_old from public, anon, authenticated;
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'rsvps_old' loop
      execute format('drop policy %I on public.rsvps_old', p.policyname);
    end loop;
  end if;
end $$;

create table if not exists public.rsvps (
  id                   uuid primary key default gen_random_uuid(),
  full_name            text not null check (char_length(full_name) between 1 and 500),
  attendance           text not null check (attendance in ('yes', 'no')),
  guest_count          integer not null default 1 check (guest_count between 0 and 30),
  adult_count          integer not null default 1 check (adult_count between 0 and 20),
  children_count       integer not null default 0 check (children_count between 0 and 20),
  dietary_requirements text check (char_length(dietary_requirements) <= 1000),
  message              text check (char_length(message) <= 2000),
  responded_at         timestamptz not null default now()
);

-- Admin passcode (hashed) and a log of passcode attempts for throttling.
create table if not exists public.rsvp_admin_settings (
  id            integer primary key default 1 check (id = 1),
  passcode_hash text not null
);
create table if not exists public.rsvp_admin_attempts (
  at timestamptz not null default now(),
  ok boolean not null
);
alter table public.rsvp_admin_attempts add column if not exists ip text;
create index if not exists rsvp_admin_attempts_at on public.rsvp_admin_attempts (at);

alter table public.rsvps                enable row level security;
alter table public.rsvp_admin_settings  enable row level security;  -- no policies: never readable from the browser
alter table public.rsvp_admin_attempts  enable row level security;  -- no policies: never readable from the browser

-- Guests may only add an RSVP; nobody can read rows directly with the public key.
revoke all on public.rsvps, public.rsvp_admin_settings, public.rsvp_admin_attempts from anon, authenticated;
grant insert on public.rsvps to anon, authenticated;

drop policy if exists "Guests can send an RSVP" on public.rsvps;
create policy "Guests can send an RSVP"
  on public.rsvps for insert
  to anon, authenticated
  with check (true);

-- Checks the passcode with throttling:
--   * 10 wrong tries from one IP address in 15 minutes locks that address for the rest of the window
--   * 20 wrong tries from all addresses together in 15 minutes locks everyone (backstop against IP rotation)
-- The address comes only from headers set by Supabase's edge, never from the client-supplied part of X-Forwarded-For.
-- Checks run one at a time (short advisory lock, no waiting inside it), so parallel requests cannot slip past the limits.
-- If you are ever locked out:  delete from public.rsvp_admin_attempts;
create or replace function public.rsvp_admin_check(p_passcode text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ok boolean;
  v_headers json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  -- cf-connecting-ip is set by Cloudflare in front of Supabase; otherwise use the rightmost
  -- X-Forwarded-For entry (appended by the proxy), never the leftmost one a client can forge
  v_ip text := coalesce(
    nullif(trim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(trim(regexp_replace(coalesce(v_headers ->> 'x-forwarded-for', ''), '^.*,', '')), ''),
    'unknown');
begin
  perform pg_advisory_xact_lock(hashtext('public.rsvp_admin_check'));

  if (select count(*) from rsvp_admin_attempts
      where not ok and ip = v_ip and at > now() - interval '15 minutes') >= 10
  or (select count(*) from rsvp_admin_attempts
      where not ok and at > now() - interval '15 minutes') >= 20 then
    return 'locked';
  end if;

  select passcode_hash = crypt(coalesce(p_passcode, ''), passcode_hash)
    into v_ok from rsvp_admin_settings where id = 1;
  v_ok := coalesce(v_ok, false);
  insert into rsvp_admin_attempts (ok, ip) values (v_ok, v_ip);
  delete from rsvp_admin_attempts where at < now() - interval '1 day';
  return case when v_ok then 'ok' else 'wrong' end;
end;
$$;

-- admin.html: every RSVP, newest first
create or replace function public.admin_list_rsvps(p_passcode text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check text := rsvp_admin_check(p_passcode);
begin
  if v_check <> 'ok' then
    return json_build_object('ok', false, 'error', v_check);
  end if;
  return json_build_object('ok', true, 'rows', coalesce(
    (select json_agg(r order by r.responded_at desc) from rsvps r), '[]'::json));
end;
$$;

-- admin.html: delete one RSVP
create or replace function public.admin_delete_rsvp(p_passcode text, p_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check text := rsvp_admin_check(p_passcode);
begin
  if v_check <> 'ok' then
    return json_build_object('ok', false, 'error', v_check);
  end if;
  delete from rsvps where id = p_id;
  return json_build_object('ok', true);
end;
$$;

revoke all on function public.rsvp_admin_check(text) from public, anon, authenticated;
revoke all on function public.admin_list_rsvps(text) from public;
revoke all on function public.admin_delete_rsvp(text, uuid) from public;
grant execute on function public.admin_list_rsvps(text) to anon, authenticated;
grant execute on function public.admin_delete_rsvp(text, uuid) to anon, authenticated;

-- ▼ Admin passcode for admin.html
insert into public.rsvp_admin_settings (id, passcode_hash)
values (1, extensions.crypt('__ADMIN_PASSCODE__', extensions.gen_salt('bf')))
on conflict (id) do update set passcode_hash = excluded.passcode_hash;
