-- Scoreboards are members-only (Nov 26, 2026)
revoke execute on function public.board_day(uuid, int), public.board_all(uuid, int) from public, anon;
grant execute on function public.board_day(uuid, int), public.board_all(uuid, int) to authenticated;
