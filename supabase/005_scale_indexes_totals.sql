-- Scale fixes (Nov 26, 2026): a game index for daily boards, and running per-player totals for all-time boards

-- 1. Daily boards look up one game's scores, highest first
create index if not exists plays_game_total_idx on public.plays (game_no, total desc);

-- 2. Running totals, kept current by a trigger on every saved game
create table if not exists public.player_totals (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  games     int not null default 0,
  total_sum bigint not null default 0,
  best      int not null default 0
);
alter table public.player_totals enable row level security;   -- no policies: read only through the board functions
revoke all on public.player_totals from anon, authenticated;

create or replace function public.np_add_total() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into player_totals as t (user_id, games, total_sum, best) values (new.user_id, 1, new.total, new.total)
  on conflict (user_id) do update set games = t.games + 1, total_sum = t.total_sum + new.total, best = greatest(t.best, new.total);
  return new;
end $$;
revoke execute on function public.np_add_total() from public, anon, authenticated;
drop trigger if exists np_add_total on public.plays;
create trigger np_add_total after insert on public.plays for each row execute function public.np_add_total();

-- backfill from games already saved (safe to re-run)
insert into public.player_totals (user_id, games, total_sum, best)
  select user_id, count(*), sum(total), max(total) from public.plays group by user_id
on conflict (user_id) do update set games = excluded.games, total_sum = excluded.total_sum, best = excluded.best;

-- 3. All-time boards read the running totals instead of averaging every saved game
create or replace function public.board_all(p_league uuid, p_min int)
returns table(pos int, username text, games int, avg numeric, best int, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid();
begin
  if p_league is null then
    return query
      with r as (
        select (rank() over (order by t.total_sum::numeric / t.games desc))::int as pos, pr.username, t.games,
               round(t.total_sum::numeric / t.games, 1) as av, t.best, (t.user_id = me) as is_me
        from player_totals t join profiles pr on pr.user_id = t.user_id
        where pr.on_global and t.games >= greatest(1, p_min))
      select * from r where r.pos <= 100 or r.is_me order by r.pos, r.username;
  else
    if me is null or not exists (select 1 from league_members m where m.league_id = p_league and m.user_id = me) then
      raise exception 'not_member'; end if;
    return query
      with a as (
        select m.user_id, coalesce(t.games, 0) g,
               case when t.games > 0 then round(t.total_sum::numeric / t.games, 1) end av, case when t.games > 0 then t.best end b
        from league_members m left join player_totals t on t.user_id = m.user_id
        where m.league_id = p_league)
      select case when a.g >= greatest(1, p_min) then (rank() over (order by case when a.g >= greatest(1, p_min) then a.av end desc nulls last))::int end,
             pr.username, a.g, a.av, a.b, (a.user_id = me)
      from a join profiles pr on pr.user_id = a.user_id
      order by case when a.g >= greatest(1, p_min) then a.av end desc nulls last, pr.username;
  end if;
end $$;
revoke execute on function public.board_all(uuid, int) from public, anon;
grant execute on function public.board_all(uuid, int) to authenticated;
