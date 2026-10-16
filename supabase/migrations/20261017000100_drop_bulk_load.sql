-- SECURITY: remove public._bulk_load(secret, q).
--
-- It was SECURITY DEFINER, executed any SQL string it was given, and was
-- callable by the anon role; its only protection was a password embedded in
-- the function body (and in tools/bulk_load.py). Anyone holding that string
-- could read or rewrite the whole database through PostgREST.
--
-- Seed files are applied with the service role (Supabase SQL editor / MCP)
-- instead.
revoke all on function public._bulk_load(text, text) from public, anon, authenticated;
drop function if exists public._bulk_load(text, text);
