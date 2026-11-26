-- Private admin dashboard (Nov 26, 2026): one function, admin_stats(), that only accounts listed in
-- np_admins can call. Powers nicepull.io/admin. Safe to re-run.

-- 1. Who counts as an admin (no direct access for anyone; read only inside admin_stats)
create table if not exists public.np_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.np_admins enable row level security;
revoke all on public.np_admins from anon, authenticated;

-- Austin's account (the Google account he signs in to Nice Pull with)
insert into public.np_admins (user_id)
  select id from auth.users where lower(email) = 'surhoffaustin@gmail.com'
on conflict do nothing;

-- 2. Everything the dashboard shows, in one call
create or replace function public.admin_stats()
returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare out jsonb;
begin
  if auth.uid() is null or not exists (select 1 from public.np_admins where user_id = auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  with ans as (                       -- one row per answer in every saved game
    select p.game_no, p.user_id, e
    from public.plays p, jsonb_array_elements(coalesce(p.results, '[]'::jsonb)) e
  )
  select jsonb_build_object(
    'generated_at',   now(),
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

    -- sign-ups and plays per day, Eastern time, last 60 days
    'signup_days', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'n', n) order by d), '[]')
                    from (select (created_at at time zone 'America/New_York')::date d, count(*) n
                          from auth.users where created_at > now() - interval '60 days' group by 1) x),
    'play_days',   (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'plays', n, 'players', u) order by d), '[]')
                    from (select (played_at at time zone 'America/New_York')::date d, count(*) n, count(distinct user_id) u
                          from public.plays where played_at > now() - interval '60 days' group by 1) x),

    -- each game: players, average / median / best / worst score
    'games', (select coalesce(jsonb_agg(jsonb_build_object('game', game_no, 'players', n, 'avg', a, 'median', m, 'best', b, 'worst', w)
                                        order by game_no), '[]')
              from (select game_no, count(*) n, round(avg(total)) a,
                           round(percentile_cont(0.5) within group (order by total)) m, max(total) b, min(total) w
                    from public.plays group by game_no) g),

    -- how often each end-of-game title is earned
    'titles', (select coalesce(jsonb_agg(jsonb_build_object('rank', rank, 'n', n) order by n desc), '[]')
               from (select coalesce(rank, '?') rank, count(*) n from public.plays group by 1) t),

    -- every answer by points earned (0 = no hit)
    'answer_pts', (select coalesce(jsonb_agg(jsonb_build_object('pts', pts, 'n', n) order by pts), '[]')
                   from (select coalesce((e->>'pts')::int, 0) pts, count(*) n from ans group by 1) t),

    -- each prompt: how people did, and the names they reach for most
    'prompts', (select coalesce(jsonb_agg(row order by (row->>'n')::int desc, row->>'q'), '[]') from (
      select jsonb_build_object(
        'q', q, 's', s, 'game', g, 'n', n,
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
      from (select e->>'q' q, max(e->>'s') s, min(game_no) g, count(*) n,
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
