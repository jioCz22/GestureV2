-- Phase 4 security hardening: return public projections instead of exposing Auth UUIDs.
revoke select,insert,update on public.profiles from anon,authenticated;
revoke all on public.profiles from anon,authenticated;
drop policy if exists "Visible profiles are viewable" on public.profiles;
create policy "Players can view their own profile row" on public.profiles for select to authenticated
 using((select auth.uid())=id);
revoke all on public.custom_stages,public.stage_levels,public.stage_reviews,public.stage_reports,public.stage_attempts,
 public.stage_favorites,public.player_challenges,public.challenge_participants from anon,authenticated;

create or replace function public.get_my_v2_profile()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select jsonb_build_object('profile',jsonb_build_object('username',p.username,'display_name',p.display_name,'avatar_url',p.avatar_url,'created_at',p.created_at),
  'xp_total',coalesce(w.verified_xp_total,0),'coin_balance',coalesce(w.verified_coin_balance,0),'settings',to_jsonb(ps),'equipped',coalesce(pa.equipped_items,'{}'::jsonb))
 into result from public.profiles p left join public.player_wallets w on w.user_id=p.id left join public.player_settings ps on ps.user_id=p.id
 left join public.player_avatar pa on pa.user_id=p.id where p.id=actor;
 return result;
end $$;

create or replace function public.get_public_stage_cards(p_category text default null,p_difficulty smallint default null,p_stage_ids uuid[] default null,p_sort text default 'recent')
returns table(id uuid,title text,description text,category text,difficulty smallint,play_count bigint,created_at timestamptz,
 author_username text,author_display_name text,prompts text[],average_rating numeric,review_count bigint)
language sql stable security definer set search_path = '' as $$
 with cards as (
  select s.id,s.title,s.description,s.category,s.difficulty,s.play_count,s.created_at,
   case when public.is_profile_public(s.author_id) then p.username else null end author_username,
   case when public.is_profile_public(s.author_id) then p.display_name else 'Jugador' end author_display_name,
   coalesce((select array_agg(u.prompt) from public.stage_levels l cross join lateral unnest(l.prompts) as u(prompt) where l.stage_id=s.id),'{}'::text[]) prompts,
   coalesce((select round(avg(r.rating),1) from public.stage_reviews r where r.stage_id=s.id),0)::numeric average_rating,
   (select count(*) from public.stage_reviews r where r.stage_id=s.id)::bigint review_count
  from public.custom_stages s join public.profiles p on p.id=s.author_id
  where s.status='published' and (p_category is null or s.category=p_category)
   and (p_difficulty is null or s.difficulty=p_difficulty) and (p_stage_ids is null or s.id=any(p_stage_ids))
 ) select c.* from cards c
 order by case when p_sort='popular' then c.play_count end desc nulls last,
  case when p_sort='rated' then c.average_rating end desc nulls last,
  case when p_sort='recommended' then c.average_rating*3+c.play_count/10.0 end desc nulls last,c.created_at desc
 limit 100
$$;
create or replace function public.get_my_favorite_stage_cards()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select coalesce(jsonb_agg(to_jsonb(cards)),'[]'::jsonb) into result
 from public.get_public_stage_cards(null,null,
  (select coalesce(array_agg(f.stage_id),'{}'::uuid[]) from public.stage_favorites f where f.user_id=actor),'recent') cards;
 return result;
end $$;
create or replace function public.get_my_stages()
returns table(id uuid,title text,status text,moderation_note text,created_at timestamptz)
language sql stable security definer set search_path = '' as $$
 select s.id,s.title,s.status,s.moderation_note,s.created_at from public.custom_stages s where s.author_id=auth.uid() order by s.created_at desc
$$;

alter table public.challenge_participants add column player_username text;
update public.challenge_participants cp set player_username=p.username from public.profiles p where p.id=cp.player_id and cp.player_username is null;
create or replace function public.fill_challenge_username()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.player_username is null then select username into new.player_username from public.profiles where id=new.player_id; end if;
 return new;
end $$;
create trigger fill_challenge_username_before_insert before insert on public.challenge_participants for each row execute function public.fill_challenge_username();
alter table public.challenge_participants alter column player_username set not null;
create or replace function public.get_my_challenges()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'join_code',c.join_code,'activity_ids',c.activity_ids,'expires_at',c.expires_at,
  'participants',(select coalesce(jsonb_agg(jsonb_build_object('username',cp.player_username,'correct_count',cp.correct_count,'elapsed_seconds',cp.elapsed_seconds,'completed_at',cp.completed_at) order by cp.started_at),'[]'::jsonb)
   from public.challenge_participants cp where cp.challenge_id=c.id)) order by c.created_at desc),'[]'::jsonb)
 into result from public.player_challenges c where c.creator_id=actor or c.opponent_id=actor;
 return result;
end $$;
revoke all on function public.get_my_v2_profile(),public.get_public_stage_cards(text,smallint,uuid[],text),
 public.get_my_favorite_stage_cards(),public.get_my_stages(),public.get_my_challenges() from public;
grant execute on function public.get_my_v2_profile() to authenticated;
grant execute on function public.get_public_stage_cards(text,smallint,uuid[],text) to anon,authenticated;
grant execute on function public.get_my_favorite_stage_cards(),public.get_my_stages(),public.get_my_challenges() to authenticated;



