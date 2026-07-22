-- Account self-deletion.
--
-- Lets an authenticated user delete their own account. Deleting the auth user
-- cascades to their persons and interactions via the ON DELETE CASCADE foreign
-- keys. Runs as SECURITY DEFINER because deleting from auth.users requires
-- elevated privileges; search_path is pinned and the function only ever targets
-- the caller's own id (auth.uid()), so a user can never delete another account.

create or replace function public.delete_current_user()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke all on function public.delete_current_user() from public, anon;
grant execute on function public.delete_current_user() to authenticated;
