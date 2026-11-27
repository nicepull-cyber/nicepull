-- Game #2 was re-issued with easier prompts on Nov 27, 2026 (Austin: "way way too hard").
-- Remove results saved for the OLD version of game 2 so those players can replay it, then rebuild the
-- running totals the all-time boards read. Results for the new version (it opens with "Homered in a World Series game")
-- are kept. Safe to re-run.
delete from public.plays
where game_no = 2
  and not (coalesce(results, '[]'::jsonb) @> '[{"q":"Homered in a World Series game"}]'::jsonb);

insert into public.player_totals (user_id, games, total_sum, best)
  select user_id, count(*), sum(total), max(total) from public.plays group by user_id
on conflict (user_id) do update set games = excluded.games, total_sum = excluded.total_sum, best = excluded.best;
delete from public.player_totals t where not exists (select 1 from public.plays p where p.user_id = t.user_id);
