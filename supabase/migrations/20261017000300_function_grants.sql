-- Hardening from the Supabase security advisor (2026-10-16).
-- Trigger functions are never called directly; signed-out users have no
-- host stats. can_post stays executable by `authenticated` because the
-- meetings RLS policies evaluate it as the signed-in user.
revoke execute on function public.profiles_mirror_trial() from public, anon, authenticated;
revoke execute on function public.set_trial_start() from public, anon, authenticated;
revoke execute on function public.host_meeting_stats(timestamptz) from public, anon;
grant execute on function public.host_meeting_stats(timestamptz) to authenticated;
