-- Nice Pull moves to 5-prompt games from Game #3 (Nov 28, 2026): prompt 4 scores ×2, prompt 5 scores ×3.
-- Saved plays may now have 5 results (new games) or 7 (games 0-2). Each result's pts must be a tier value
-- times that prompt's multiplier, and the results must add up to the total.
create or replace function public.np_check_play()
 returns trigger
 language plpgsql
as $function$
declare
  latest int := ((now() at time zone 'Pacific/Kiritimati')::date - date '2026-11-26') + 1;
  len int; n int; s int;
  base int[] := array[0,10,25,30,40,60,80,100];
begin
  if new.game_no > latest then raise exception 'game_not_out'; end if;
  if jsonb_typeof(new.results) <> 'array' then raise exception 'bad_results'; end if;
  len := jsonb_array_length(new.results);
  if len not in (5, 7) then raise exception 'bad_results'; end if;
  select count(*), coalesce(sum((x->>'pts')::int), 0) into n, s
    from jsonb_array_elements(new.results) with ordinality as e(x, k)
   where (x->>'pts') ~ '^[0-9]+$'
     and (x->>'pts')::int = any (
       select b * (case when len = 5 and k = 4 then 2 when len = 5 and k = 5 then 3 else 1 end) from unnest(base) b);
  if n <> len or s <> new.total then raise exception 'bad_total'; end if;
  return new;
end $function$;
