-- Nice Pull: usernames, global scoreboard, leagues (run once in the Supabase SQL editor)

-- ---------- usernames ----------
create table if not exists public.profiles (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  username   text not null check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  on_global  boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_key on public.profiles (lower(username));
alter table public.profiles enable row level security;
drop policy if exists "read own profile" on public.profiles;
drop policy if exists "add own profile"  on public.profiles;
drop policy if exists "edit own profile" on public.profiles;
create policy "read own profile" on public.profiles for select to authenticated using (user_id = auth.uid());
create policy "add own profile"  on public.profiles for insert to authenticated with check (user_id = auth.uid());
create policy "edit own profile" on public.profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.profiles from anon, authenticated;
grant select, insert on public.profiles to authenticated;
grant update (username, on_global) on public.profiles to authenticated;

create or replace function public.np_username_ok(p text) returns boolean language sql immutable as $$
  select p ~ '^[A-Za-z0-9_]{3,20}$'
     and lower(p) !~ '(nicepull|admin|support|moderator|official|fuck|shit|cunt|nigg|fag|retard|whore|slut|bitch|pussy|nazi|hitler|kike|chink|tranny)'
$$;
create or replace function public.np_check_profile() returns trigger language plpgsql as $$
begin
  if not public.np_username_ok(new.username) then raise exception 'username_blocked'; end if;
  return new;
end $$;
drop trigger if exists np_check_profile on public.profiles;
create trigger np_check_profile before insert or update on public.profiles for each row execute function public.np_check_profile();

create or replace function public.username_available(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.np_username_ok(p_name) and not exists (
    select 1 from profiles where lower(username) = lower(p_name) and user_id is distinct from auth.uid())
$$;

-- ---------- sanity checks on saved games (blocks future games and made-up totals) ----------
create or replace function public.np_check_play() returns trigger language plpgsql as $$
declare
  latest int := ((now() at time zone 'Pacific/Kiritimati')::date - date '2026-11-25') + 1;  -- earliest time zone on Earth
  n int; s int;
begin
  if new.game_no > latest then raise exception 'game_not_out'; end if;
  if jsonb_typeof(new.results) <> 'array' or jsonb_array_length(new.results) <> 7 then raise exception 'bad_results'; end if;
  select count(*), coalesce(sum((x->>'pts')::int), 0) into n, s
    from jsonb_array_elements(new.results) x where (x->>'pts') in ('0','10','25','40','60','80','100');
  if n <> 7 or s <> new.total then raise exception 'bad_total'; end if;
  return new;
end $$;
drop trigger if exists np_check_play on public.plays;
create trigger np_check_play before insert on public.plays for each row execute function public.np_check_play();

-- ---------- leagues ----------
create table if not exists public.leagues (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 2 and 32),
  code       text not null unique,
  owner      uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.league_members (
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
alter table public.leagues enable row level security;          -- no policies: reached only through the functions below
alter table public.league_members enable row level security;
revoke all on public.leagues, public.league_members from anon, authenticated;

create or replace function public.create_league(p_name text) returns table(id uuid, name text, code text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); v_id uuid; v_code text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from profiles p where p.user_id = me) then raise exception 'no_username'; end if;
  if (select count(*) from leagues l where l.owner = me) >= 10 then raise exception 'too_many_leagues'; end if;
  insert into leagues(name, code, owner) values (btrim(p_name), v_code, me) returning leagues.id into v_id;
  insert into league_members(league_id, user_id) values (v_id, me);
  return query select l.id, l.name, l.code from leagues l where l.id = v_id;
end $$;

create or replace function public.league_preview(p_code text) returns table(name text, members int)
language sql stable security definer set search_path = public as $$
  select l.name, (select count(*)::int from league_members m where m.league_id = l.id)
  from leagues l where l.code = lower(btrim(p_code))
$$;

create or replace function public.join_league(p_code text) returns table(id uuid, name text, code text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); v_id uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from profiles p where p.user_id = me) then raise exception 'no_username'; end if;
  select l.id into v_id from leagues l where l.code = lower(btrim(p_code));
  if v_id is null then raise exception 'league_not_found'; end if;
  if not exists (select 1 from league_members m where m.league_id = v_id and m.user_id = me) then
    if (select count(*) from league_members m where m.league_id = v_id) >= 200 then raise exception 'league_full'; end if;
    insert into league_members(league_id, user_id) values (v_id, me);
  end if;
  return query select l.id, l.name, l.code from leagues l where l.id = v_id;
end $$;

create or replace function public.leave_league(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from league_members m where m.league_id = p_id and m.user_id = auth.uid();
  delete from leagues l where l.id = p_id and not exists (select 1 from league_members m where m.league_id = p_id);
end $$;

create or replace function public.my_leagues() returns table(id uuid, name text, code text, members int, is_owner boolean)
language sql stable security definer set search_path = public as $$
  select l.id, l.name, l.code, (select count(*)::int from league_members x where x.league_id = l.id), l.owner = auth.uid()
  from leagues l join league_members m on m.league_id = l.id and m.user_id = auth.uid()
  order by m.joined_at
$$;

-- one game's board: global (p_league null) or a league; league boards also list members who haven't played
create or replace function public.board_day(p_league uuid, p_game int)
returns table(pos int, username text, total int, rank text, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid();
begin
  if p_league is null then
    return query
      with r as (
        select (rank() over (order by p.total desc))::int as pos, pr.username, p.total, p.rank, (p.user_id = me) as is_me
        from plays p join profiles pr on pr.user_id = p.user_id
        where p.game_no = p_game and pr.on_global)
      select * from r where r.pos <= 100 or r.is_me order by r.pos, r.username;
  else
    if me is null or not exists (select 1 from league_members m where m.league_id = p_league and m.user_id = me) then
      raise exception 'not_member'; end if;
    return query
      select case when p.total is null then null else (rank() over (order by p.total desc nulls last))::int end,
             pr.username, p.total, p.rank, (m.user_id = me)
      from league_members m join profiles pr on pr.user_id = m.user_id
      left join plays p on p.user_id = m.user_id and p.game_no = p_game
      where m.league_id = p_league
      order by p.total desc nulls last, pr.username;
  end if;
end $$;

-- all-time board: ranked by average score; p_min = fewest games to qualify
create or replace function public.board_all(p_league uuid, p_min int)
returns table(pos int, username text, games int, avg numeric, best int, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid();
begin
  if p_league is null then
    return query
      with a as (
        select p.user_id, count(*)::int g, round(avg(p.total), 1) av, max(p.total) b
        from plays p join profiles pr on pr.user_id = p.user_id where pr.on_global
        group by p.user_id having count(*) >= greatest(1, p_min)),
      r as (
        select (rank() over (order by a.av desc))::int as pos, pr.username, a.g, a.av, a.b, (a.user_id = me) as is_me
        from a join profiles pr on pr.user_id = a.user_id)
      select * from r where r.pos <= 100 or r.is_me order by r.pos, r.username;
  else
    if me is null or not exists (select 1 from league_members m where m.league_id = p_league and m.user_id = me) then
      raise exception 'not_member'; end if;
    return query
      with a as (
        select m.user_id, count(p.game_no)::int g, round(avg(p.total), 1) av, max(p.total) b
        from league_members m left join plays p on p.user_id = m.user_id
        where m.league_id = p_league group by m.user_id)
      select case when a.g >= greatest(1, p_min) then (rank() over (order by case when a.g >= greatest(1, p_min) then a.av end desc nulls last))::int end,
             pr.username, a.g, a.av, a.b, (a.user_id = me)
      from a join profiles pr on pr.user_id = a.user_id
      order by case when a.g >= greatest(1, p_min) then a.av end desc nulls last, pr.username;
  end if;
end $$;

-- who can call what
revoke execute on function public.username_available(text), public.create_league(text), public.league_preview(text),
  public.join_league(text), public.leave_league(uuid), public.my_leagues(), public.board_day(uuid, int), public.board_all(uuid, int)
  from public, anon;
grant execute on function public.username_available(text), public.create_league(text), public.join_league(text),
  public.leave_league(uuid), public.my_leagues() to authenticated;
grant execute on function public.league_preview(text) to anon, authenticated;     -- invite card works before sign-in
grant execute on function public.board_day(uuid, int), public.board_all(uuid, int) to authenticated;  -- scoreboards are members-only
