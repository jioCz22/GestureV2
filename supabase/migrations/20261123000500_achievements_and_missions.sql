-- Phase 2–3 supporting reads: achievement awards, daily mission state, creator stats.
create table public.achievement_catalog(
 achievement_key text primary key,title text not null,description text not null,metric text not null,goal integer not null check(goal>0)
);
insert into public.achievement_catalog values
('first_activity','Primer paso','Completa tu primera actividad.','activities',1),
('letters10','Explorador del alfabeto','Completa diez letras.','letters',10),
('alphabet','Alfabeto completo','Completa las 26 letras.','letters',26),
('word10','Constructor de palabras','Completa diez palabras.','words',10),
('xp500','Aprendiz constante','Acumula 500 XP.','xp',500)
on conflict do nothing;
create or replace function public.award_eligible_achievements()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor uuid:=new.user_id;
begin
 insert into public.player_achievements(user_id,achievement_key)
 select actor,a.achievement_key from public.achievement_catalog a
 where case a.metric
   when 'activities' then (select count(*) from public.experience_transactions e where e.user_id=actor and e.verified)>=a.goal
   when 'letters' then (select count(*) from public.experience_transactions e join public.activity_catalog c on c.activity_id=e.activity_id where e.user_id=actor and c.activity_type='letter' and e.verified)>=a.goal
   when 'words' then (select count(*) from public.experience_transactions e join public.activity_catalog c on c.activity_id=e.activity_id where e.user_id=actor and c.activity_type='word' and e.verified)>=a.goal
   when 'xp' then (select coalesce(sum(e.amount),0) from public.experience_transactions e where e.user_id=actor and e.verified)>=a.goal
   else false end
 on conflict do nothing;
 return new;
end $$;
create trigger award_achievements_after_xp after insert on public.experience_transactions
for each row execute function public.award_eligible_achievements();
create table public.daily_missions(
 mission_key text primary key,title text not null,description text not null,target integer not null check(target>0),coin_reward integer not null check(coin_reward>0),active boolean not null default true
);
insert into public.daily_missions values('daily_three_activities','Práctica diaria','Completa tres actividades de aprendizaje.',3,25,true) on conflict do nothing;
alter table public.achievement_catalog enable row level security;
alter table public.daily_missions enable row level security;

create or replace function public.get_daily_mission_status()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); done integer; claimed boolean;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select count(*) into done from public.experience_transactions where user_id=actor and verified and created_at >= ((date_trunc('day',now() at time zone 'UTC')) at time zone 'UTC');
 select exists(select 1 from public.mission_claims where user_id=actor and mission_key='daily_three_activities' and period_start=(now() at time zone 'UTC')::date) into claimed;
 return jsonb_build_object('completed',done,'target',3,'claimed',claimed,'reward',25);
end $$;
create or replace function public.get_creator_stats()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select jsonb_build_object('created',count(*),'published',count(*) filter(where status='published'),
   'pending',count(*) filter(where status='pending_review'),
   'participants',coalesce(sum((select count(*) from public.stage_attempts a where a.stage_id=s.id)),0))
 into result from public.custom_stages s where author_id=actor;
 return coalesce(result,'{}'::jsonb);
end $$;
revoke all on function public.get_daily_mission_status(),public.get_creator_stats() from public,anon;
grant execute on function public.get_daily_mission_status(),public.get_creator_stats() to authenticated;
revoke all on public.achievement_catalog,public.daily_missions from anon,authenticated;

