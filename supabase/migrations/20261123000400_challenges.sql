-- Phase 3: peer challenges with results derived from the server reward ledger.
create table public.player_challenges (
 id uuid primary key default gen_random_uuid(),creator_id uuid not null references public.profiles(id) on delete cascade,
 opponent_id uuid not null references public.profiles(id) on delete cascade,
 join_code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
 activity_ids text[] not null check(cardinality(activity_ids) between 1 and 20),
 created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '14 days',
 check(creator_id<>opponent_id)
);
create table public.challenge_participants (
 challenge_id uuid not null references public.player_challenges(id) on delete cascade,
 player_id uuid not null references public.profiles(id) on delete cascade,
 started_at timestamptz not null default now(),correct_count integer not null default 0 check(correct_count>=0),
 elapsed_seconds integer,completed_at timestamptz,primary key(challenge_id,player_id)
);
alter table public.player_challenges enable row level security;
alter table public.challenge_participants enable row level security;
revoke all on public.player_challenges,public.challenge_participants from anon,authenticated;
grant select on public.player_challenges,public.challenge_participants to authenticated;
create policy "Challenge members see their challenge" on public.player_challenges for select to authenticated
 using((select auth.uid())=creator_id or (select auth.uid())=opponent_id);
create policy "Challenge members see results" on public.challenge_participants for select to authenticated
 using(exists(select 1 from public.player_challenges c where c.id=challenge_id and ((select auth.uid())=c.creator_id or (select auth.uid())=c.opponent_id)));

create or replace function public.create_player_challenge(p_opponent_username text,p_activity_ids text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); opponent uuid; cid uuid; code text;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if p_activity_ids is null or cardinality(p_activity_ids) not between 1 and 20 then raise exception 'Choose 1–20 activities'; end if;
 if (select count(distinct k) from unnest(p_activity_ids) k)<>cardinality(p_activity_ids) then raise exception 'Remove duplicate activities'; end if;
 if exists(select 1 from unnest(p_activity_ids) k where not exists(select 1 from public.activity_catalog a where a.activity_id=k)) then raise exception 'Unknown challenge activity'; end if;
 select id into opponent from public.profiles where lower(username)=lower(trim(p_opponent_username)) and public.is_profile_public(id);
 if opponent is null or opponent=actor then raise exception 'Player not found'; end if;
 insert into public.player_challenges(creator_id,opponent_id,activity_ids) values(actor,opponent,p_activity_ids) returning id,join_code into cid,code;
 insert into public.challenge_participants(challenge_id,player_id) values(cid,actor);
 return jsonb_build_object('id',cid,'join_code',code);
end $$;
create or replace function public.join_player_challenge(p_join_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); cid uuid;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select id into cid from public.player_challenges where upper(join_code)=upper(trim(p_join_code)) and opponent_id=actor and expires_at>now();
 if cid is null then raise exception 'Challenge not found or expired'; end if;
 insert into public.challenge_participants(challenge_id,player_id) values(cid,actor) on conflict do nothing;
 return cid;
end $$;
create or replace function public.complete_player_challenge(p_challenge_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); challenge public.player_challenges%rowtype; started timestamptz; total integer; correct integer; elapsed integer;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select * into challenge from public.player_challenges where id=p_challenge_id and (creator_id=actor or opponent_id=actor) and expires_at>now();
 if not found then raise exception 'Challenge not found or expired'; end if;
 insert into public.challenge_participants(challenge_id,player_id) values(challenge.id,actor) on conflict do nothing;
 select started_at into started from public.challenge_participants where challenge_id=challenge.id and player_id=actor for update;
 total:=cardinality(challenge.activity_ids);
 select count(*) into correct from public.experience_transactions e
   where e.user_id=actor and e.activity_id=any(challenge.activity_ids) and e.created_at>=started;
 select greatest(0,extract(epoch from (now()-started))::integer) into elapsed;
 update public.challenge_participants set correct_count=correct,elapsed_seconds=elapsed,completed_at=now()
   where challenge_id=challenge.id and player_id=actor;
 return jsonb_build_object('correct',correct,'total',total,'elapsed_seconds',elapsed);
end $$;
revoke all on function public.create_player_challenge(text,text[]),public.join_player_challenge(text),public.complete_player_challenge(uuid) from public,anon;
grant execute on function public.create_player_challenge(text,text[]),public.join_player_challenge(text),public.complete_player_challenge(uuid) to authenticated;

create table public.challenge_activity_completions(
 challenge_id uuid not null references public.player_challenges(id) on delete cascade,
 player_id uuid not null references public.profiles(id) on delete cascade,
 activity_id text not null references public.activity_catalog(activity_id),
 completed_at timestamptz not null default now(),primary key(challenge_id,player_id,activity_id)
);
alter table public.challenge_activity_completions enable row level security;
revoke all on public.challenge_activity_completions from anon,authenticated;
create or replace function public.record_challenge_activity(p_activity_type text,p_activity_key text)
returns integer language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); v_activity_id text; inserted_count integer;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select activity_id into v_activity_id from public.activity_catalog where activity_type=p_activity_type and activity_key=p_activity_key;
 if activity is null then raise exception 'Unknown learning activity'; end if;
 insert into public.challenge_activity_completions(challenge_id,player_id,activity_id)
 select c.id,actor,v_activity_id from public.player_challenges c join public.challenge_participants cp on cp.challenge_id=c.id and cp.player_id=actor
 where c.expires_at>now() and v_activity_id=any(c.activity_ids) on conflict do nothing;
 get diagnostics inserted_count=row_count;
 return inserted_count;
end $$;
create or replace function public.complete_player_challenge(p_challenge_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); challenge public.player_challenges%rowtype; started timestamptz; total integer; correct integer; elapsed integer;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select * into challenge from public.player_challenges where id=p_challenge_id and (creator_id=actor or opponent_id=actor) and expires_at>now();
 if not found then raise exception 'Challenge not found or expired'; end if;
 select started_at into started from public.challenge_participants where challenge_id=challenge.id and player_id=actor for update;
 if started is null then raise exception 'Join the challenge first'; end if;
 total:=cardinality(challenge.activity_ids);
 select count(*),coalesce(extract(epoch from(max(completed_at)-started))::integer,0) into correct,elapsed
 from public.challenge_activity_completions where challenge_id=challenge.id and player_id=actor;
 update public.challenge_participants set correct_count=correct,elapsed_seconds=greatest(0,elapsed),completed_at=now()
 where challenge_id=challenge.id and player_id=actor;
 return jsonb_build_object('correct',correct,'total',total,'elapsed_seconds',greatest(0,elapsed));
end $$;
revoke all on function public.record_challenge_activity(text,text) from public,anon;
grant execute on function public.record_challenge_activity(text,text) to authenticated;
