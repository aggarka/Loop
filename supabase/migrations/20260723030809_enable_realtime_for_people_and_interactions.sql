-- Enable Realtime for people and interactions.
--
-- Adds the tables to the `supabase_realtime` publication so Postgres changes are
-- broadcast to subscribed clients. RLS still applies: each client only receives
-- changes to rows it is allowed to see. Idempotent — skips tables already in the
-- publication.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'persons'
  ) then
    alter publication supabase_realtime add table public.persons;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'interactions'
  ) then
    alter publication supabase_realtime add table public.interactions;
  end if;
end $$;
