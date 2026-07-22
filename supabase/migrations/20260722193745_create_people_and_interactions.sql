-- Loop: people and interactions schema with row level security.
--
-- Each row is owned by an authenticated user (owner_user_id = auth.uid()).
-- Row Level Security ensures a user can only read and write their own records.
-- Records use client-generated UUID ids so the app can create rows offline and
-- reconcile via sync. Deletes are soft (is_tombstoned) so they propagate.

-- ============================================================================
-- persons
-- ============================================================================
create table if not exists public.persons (
  id                  uuid primary key,
  owner_user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                text not null,
  company             text,
  title               text,
  email               text,
  phone               text,
  tags                text[] not null default '{}',
  source              text not null default 'manual',
  last_contacted_date timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  is_tombstoned       boolean not null default false
);

create index if not exists persons_owner_idx on public.persons (owner_user_id);
create index if not exists persons_updated_at_idx on public.persons (owner_user_id, updated_at);

-- ============================================================================
-- interactions
-- ============================================================================
create table if not exists public.interactions (
  id                 uuid primary key,
  owner_user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  person_id          uuid not null references public.persons (id) on delete cascade,
  date               timestamptz not null,
  type               text not null,
  notes              text not null default '',
  outcomes           text,
  ai_summary         text,
  follow_up_date     timestamptz,
  follow_up_status   text not null default 'none',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  is_tombstoned      boolean not null default false
);

create index if not exists interactions_owner_idx on public.interactions (owner_user_id);
create index if not exists interactions_person_idx on public.interactions (person_id);
create index if not exists interactions_updated_at_idx on public.interactions (owner_user_id, updated_at);

-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table public.persons enable row level security;
alter table public.interactions enable row level security;

-- persons policies (one per operation, scoped to the authenticated owner).
create policy "Users can view their own persons"
  on public.persons for select to authenticated
  using ( (select auth.uid()) = owner_user_id );

create policy "Users can insert their own persons"
  on public.persons for insert to authenticated
  with check ( (select auth.uid()) = owner_user_id );

create policy "Users can update their own persons"
  on public.persons for update to authenticated
  using ( (select auth.uid()) = owner_user_id )
  with check ( (select auth.uid()) = owner_user_id );

create policy "Users can delete their own persons"
  on public.persons for delete to authenticated
  using ( (select auth.uid()) = owner_user_id );

-- interactions policies.
create policy "Users can view their own interactions"
  on public.interactions for select to authenticated
  using ( (select auth.uid()) = owner_user_id );

create policy "Users can insert their own interactions"
  on public.interactions for insert to authenticated
  with check ( (select auth.uid()) = owner_user_id );

create policy "Users can update their own interactions"
  on public.interactions for update to authenticated
  using ( (select auth.uid()) = owner_user_id )
  with check ( (select auth.uid()) = owner_user_id );

create policy "Users can delete their own interactions"
  on public.interactions for delete to authenticated
  using ( (select auth.uid()) = owner_user_id );

-- ============================================================================
-- Table-level privileges
-- RLS restricts WHICH rows the authenticated role sees; these grants provide the
-- base table access that RLS then narrows to the owner's rows.
-- ============================================================================
grant select, insert, update, delete on public.persons to authenticated;
grant select, insert, update, delete on public.interactions to authenticated;
