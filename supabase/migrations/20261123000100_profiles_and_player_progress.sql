-- GestureChallenge v2.0 foundations: public profile and private learning progress.
-- Apply to a local Supabase project first. No XP, coins, rankings, or purchase
-- authority is stored here; those require trusted server-side operations later.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[a-zA-Z0-9_]{3,20}$'),
  display_name text not null default 'Jugador' check (char_length(display_name) between 1 and 40),
  avatar_url text,
  created_at timestamptz not null default now()
);

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));

create table if not exists public.player_progress (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  completed_letters text[] not null default '{}',
  completed_words text[] not null default '{}',
  completed_phrases text[] not null default '{}',
  completed_levels integer[] not null default '{}',
  mastery jsonb not null default '{}'::jsonb check (jsonb_typeof(mastery) = 'object'),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  proposed_username text;
  proposed_display_name text;
begin
  proposed_username := lower(regexp_replace(coalesce(new.raw_user_meta_data ->> 'username', ''), '[^a-zA-Z0-9_]', '', 'g'));
  proposed_display_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');

  if char_length(proposed_username) < 3 or char_length(proposed_username) > 20 then
    proposed_username := 'jugador_' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    proposed_username,
    coalesce(left(proposed_display_name, 40), 'Jugador')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.player_progress enable row level security;

revoke all on public.profiles from anon, authenticated;
revoke all on public.player_progress from anon, authenticated;
-- Profile rows are accessed only through privacy-aware SECURITY DEFINER projections.
revoke all on public.profiles from anon, authenticated;
grant select, insert, update, delete on public.player_progress to authenticated;

drop policy if exists "Public profiles are viewable" on public.profiles;
drop policy if exists "Players can update their profile" on public.profiles;

drop policy if exists "Players can read their progress" on public.player_progress;
create policy "Players can read their progress"
  on public.player_progress for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Players can create their progress" on public.player_progress;
create policy "Players can create their progress"
  on public.player_progress for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Players can update their progress" on public.player_progress;
create policy "Players can update their progress"
  on public.player_progress for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Players can delete their progress" on public.player_progress;
create policy "Players can delete their progress"
  on public.player_progress for delete to authenticated
  using ((select auth.uid()) = user_id);
