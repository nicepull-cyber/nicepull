-- Role Player retired, Box Score Guy now 30 (Nov 26, 2026). 25 and 40 stay valid for games played before the change.
create or replace function public.np_check_play() returns trigger language plpgsql as $$
declare
  latest int := ((now() at time zone 'Pacific/Kiritimati')::date - date '2026-11-25') + 1;  -- earliest time zone on Earth
  n int; s int;
begin
  if new.game_no > latest then raise exception 'game_not_out'; end if;
  if jsonb_typeof(new.results) <> 'array' or jsonb_array_length(new.results) <> 7 then raise exception 'bad_results'; end if;
  select count(*), coalesce(sum((x->>'pts')::int), 0) into n, s
    from jsonb_array_elements(new.results) x where (x->>'pts') in ('0','10','25','30','40','60','80','100');
  if n <> 7 or s <> new.total then raise exception 'bad_total'; end if;
  return new;
end $$;
