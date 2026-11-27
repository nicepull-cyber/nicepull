-- Anonymous finished-game log (Nov 27, 2026). Austin: "stick to best practices, only as invasive as a typical game."
-- Every finished game, signed in or not: game, score, title and the 7 answers. No user id, no IP, no device id,
-- no cookie. prior_games / days_since_last are counted by the player's own browser from its saved scores, so we
-- can tell new players from returning ones without identifying anyone. Insert-only from the site; nobody can read
-- it except through admin_stats(). Safe to re-run.
create table if not exists public.finishes (
  id bigint generated always as identity primary key,
  game_no int not null check (game_no >= 0),
  played_at timestamptz not null default now(),
  total int not null check (total between 0 and 700),
  rank text check (char_length(rank) <= 60),
  results jsonb not null check (pg_column_size(results) < 8000),
  signed_in boolean not null default false,
  prior_games int check (prior_games between 0 and 10000),
  days_since_last int check (days_since_last between 0 and 10000)
);
alter table public.finishes enable row level security;
revoke all on public.finishes from anon, authenticated;
grant insert (game_no, total, rank, results, signed_in, prior_games, days_since_last) on public.finishes to anon, authenticated;
drop policy if exists finishes_insert on public.finishes;
create policy finishes_insert on public.finishes for insert to anon, authenticated with check (true);

create or replace function public.np_finish_stamp() returns trigger language plpgsql as $$
begin new.played_at := now(); return new; end $$;          -- the server sets the time
drop trigger if exists finishes_stamp on public.finishes;
create trigger finishes_stamp before insert on public.finishes for each row execute function public.np_finish_stamp();
drop trigger if exists finishes_check on public.finishes;  -- same checks as saved plays: game is out, 7 answers, total adds up
create trigger finishes_check before insert on public.finishes for each row execute function public.np_check_play();
create index if not exists finishes_game_idx on public.finishes (game_no);
create index if not exists finishes_played_idx on public.finishes (played_at);

-- admin_stats(): add everyone's finished games. Score, title and prompt sections now use finishes, plus signed-in
-- plays saved before finishes started (so nothing is counted twice).
create or replace function public.admin_stats()
returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare out jsonb; cutoff timestamptz;
begin
  if auth.uid() is null or not exists (select 1 from public.np_admins where user_id = auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce(min(played_at), now()) into cutoff from public.finishes;

  with g as (
    select game_no, total, rank, results, played_at, prior_games from public.finishes
    union all
    select game_no, total, rank, results, played_at, null::int from public.plays where played_at < cutoff
  ), ans as (
    select g.game_no, e from g, jsonb_array_elements(coalesce(g.results, '[]'::jsonb)) e
  )
  select jsonb_build_object(
    'generated_at',   now(),
    'finishes_since', cutoff,
    'signups',        (select count(*) from auth.users),
    'signups_24h',    (select count(*) from auth.users where created_at > now() - interval '24 hours'),
    'signups_7d',     (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'usernames',      (select count(*) from public.profiles),
    'on_global',      (select count(*) from public.profiles where on_global),
    'leagues',        (select count(*) from public.leagues),
    'league_members', (select count(*) from public.league_members),
    'players',        (select count(distinct user_id) from public.plays),
    'plays',          (select count(*) from public.plays),
    'active_24h',     (select count(distinct user_id) from public.plays where played_at > now() - interval '24 hours'),
    'returning',      (select count(*) from (select user_id from public.plays group by user_id having count(*) > 1) r),
    'finished',       (select count(*) from public.finishes),
    'finished_24h',   (select count(*) from public.finishes where played_at > now() - interval '24 hours'),
    'finished_signed',(select count(*) from public.finishes where signed_in),
    'finished_back',  (select count(*) from public.finishes where prior_games > 0),
    'signup_days', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'n', n) order by d), '[]')
                    from (select (created_at at time zone 'America/New_York')::date d, count(*) n
                          from auth.users where created_at > now() - interval '60 days' group by 1) x),
    'play_days',   (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'plays', n, 'players', n, 'back', b) order by d), '[]')
                    from (select (played_at at time zone 'America/New_York')::date d, count(*) n,
                                 count(*) filter (where prior_games > 0) b
                          from g where played_at > now() - interval '60 days' group by 1) x),
    'games', (select coalesce(jsonb_agg(jsonb_build_object('game', game_no, 'players', n, 'avg', a, 'median', m, 'best', b, 'worst', w)
                                        order by game_no), '[]')
              from (select game_no, count(*) n, round(avg(total)) a,
                           round(percentile_cont(0.5) within group (order by total)) m, max(total) b, min(total) w
                    from g group by game_no) gg),
    'titles', (select coalesce(jsonb_agg(jsonb_build_object('rank', rank, 'n', n) order by n desc), '[]')
               from (select coalesce(rank, '?') rank, count(*) n from g group by 1) t),
    'answer_pts', (select coalesce(jsonb_agg(jsonb_build_object('pts', pts, 'n', n) order by pts), '[]')
                   from (select coalesce((e->>'pts')::int, 0) pts, count(*) n from ans group by 1) t),
    'prompts', (select coalesce(jsonb_agg(row order by (row->>'n')::int desc, row->>'q'), '[]') from (
      select jsonb_build_object(
        'q', q, 's', s, 'game', gm, 'n', n,
        'avg_pts', round(avg_pts, 1),
        'hit', round(100.0 * hits / nullif(n, 0)),
        'timeouts', timeouts,
        'beast', beast,
        'top', (select coalesce(jsonb_agg(jsonb_build_object('name', nm, 'n', c, 'pts', pp) order by c desc, nm), '[]')
                from (select a2.e->>'name' nm, count(*) c, max(coalesce((a2.e->>'pts')::int, 0)) pp
                      from ans a2
                      where a2.e->>'q' = pq.q and a2.e->>'name' is not null and coalesce((a2.e->>'t')::int, -1) >= 0
                      group by 1 order by 2 desc, 1 limit 5) tn)
      ) row
      from (select e->>'q' q, max(e->>'s') s, min(game_no) gm, count(*) n,
                   avg(coalesce((e->>'pts')::numeric, 0)) avg_pts,
                   count(*) filter (where coalesce((e->>'t')::int, -1) >= 0) hits,
                   count(*) filter (where (e->>'timeout')::boolean) timeouts,
                   count(*) filter (where coalesce((e->>'pts')::int, 0) = 100) beast
            from ans where e->>'q' is not null group by e->>'q') pq
    ) pr)
  ) into out;
  return out;
end $$;
revoke execute on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;
