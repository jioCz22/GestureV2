-- Phase 2/4: short server-issued assessment sessions; scores are calculated and stored server-side.
create table public.player_assessment_sessions(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 questions jsonb not null check(jsonb_typeof(questions)='array'),started_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '10 minutes',submitted_at timestamptz
);
create table public.player_assessment_scores(
 session_id uuid primary key references public.player_assessment_sessions(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,correct integer not null check(correct>=0),
 total integer not null check(total>0),accuracy_percent smallint not null check(accuracy_percent between 0 and 100),
 created_at timestamptz not null default now()
);
alter table public.player_assessment_sessions enable row level security;
alter table public.player_assessment_scores enable row level security;
revoke all on public.player_assessment_sessions,public.player_assessment_scores from anon,authenticated;
grant select on public.player_assessment_scores to authenticated;
create policy "Players read own assessment scores" on public.player_assessment_scores for select to authenticated using((select auth.uid())=user_id);

create or replace function public.start_learning_assessment()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); questions jsonb; session_id uuid;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if (select count(*) from public.player_assessment_sessions where user_id=actor and started_at>=date_trunc('day',now()))>=10 then raise exception 'Daily assessment limit reached'; end if;
 select jsonb_agg(jsonb_build_object('id',q.qid,'target',q.target,'choices',q.choices) order by q.n) into questions
 from (
  select row_number() over() n,gen_random_uuid()::text qid,letter target,
   (select jsonb_agg(choice order by random()) from unnest(array_append(array(select activity_key from public.activity_catalog where activity_type='letter' and activity_key<>letter order by random() limit 3),letter)) choice) choices
  from (select activity_key letter from public.activity_catalog where activity_type='letter' order by random() limit 10) picked
 ) q;
 insert into public.player_assessment_sessions(user_id,questions) values(actor,questions) returning id into session_id;
 return jsonb_build_object('session_id',session_id,'questions',questions,'expires_at',now()+interval '10 minutes');
end $$;
create or replace function public.submit_learning_assessment(p_session_id uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); session public.player_assessment_sessions%rowtype; total integer; correct integer; accuracy smallint;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if jsonb_typeof(p_answers)<>'array' then raise exception 'Answers must be an array'; end if;
 select * into session from public.player_assessment_sessions where id=p_session_id and user_id=actor for update;
 if not found or session.expires_at<now() or session.submitted_at is not null then raise exception 'Assessment expired or already submitted'; end if;
 total:=jsonb_array_length(session.questions);
 if jsonb_array_length(p_answers)<>total then raise exception 'Answer every question exactly once'; end if;
 if exists(select 1 from jsonb_array_elements(p_answers) a group by a->>'id' having count(*)>1) then raise exception 'Duplicate answers are not allowed'; end if;
 if exists(select 1 from jsonb_array_elements(p_answers) a where not exists(select 1 from jsonb_array_elements(session.questions) q where q->>'id'=a->>'id')) then raise exception 'Unknown question'; end if;
 select count(*) into correct from jsonb_array_elements(session.questions) q
 where exists(select 1 from jsonb_array_elements(p_answers) a where a->>'id'=q->>'id' and a->>'answer'=q->>'target');
 accuracy:=round(correct*100.0/total)::smallint;
 update public.player_assessment_sessions set submitted_at=now() where id=p_session_id;
 insert into public.player_assessment_scores(session_id,user_id,correct,total,accuracy_percent) values(p_session_id,actor,correct,total,accuracy);
 return jsonb_build_object('correct',correct,'total',total,'accuracy_percent',accuracy);
end $$;

create or replace function public.get_learning_leaderboard(p_metric text default 'experience',p_weekly boolean default false)
returns table(username text,display_name text,score bigint,position bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
 if p_metric not in ('experience','mastery','consistency','weekly_activity','precision') then raise exception 'Unknown ranking metric'; end if;
 return query
 with visible as (
  select p.id,p.username,p.display_name,coalesce(w.xp_total,0) xp_total,
   (select count(*) from public.experience_transactions e where e.user_id=p.id) completed,
   (select count(distinct (e.created_at at time zone 'UTC')::date) from public.experience_transactions e where e.user_id=p.id and e.created_at>=now()-case when p_weekly then interval '7 days' else interval '30 days' end) active_days,
   (select count(*) from public.experience_transactions e where e.user_id=p.id and e.created_at>=now()-interval '7 days') weekly_count,
   (select coalesce(sum(e.amount),0) from public.experience_transactions e where e.user_id=p.id and e.created_at>=now()-interval '7 days') weekly_xp,
   (select coalesce(round(avg(a.accuracy_percent)),0) from public.player_assessment_scores a where a.user_id=p.id and (not p_weekly or a.created_at>=now()-interval '7 days')) precision_score
  from public.profiles p join public.player_settings ps on ps.user_id=p.id and ps.show_profile and ps.show_xp
  left join public.player_wallets w on w.user_id=p.id
 ), scored as (
  select v.username,v.display_name,case p_metric when 'experience' then case when p_weekly then v.weekly_xp else v.xp_total end
    when 'mastery' then v.completed when 'consistency' then v.active_days when 'weekly_activity' then v.weekly_count when 'precision' then v.precision_score end::bigint score
  from visible v
 ) select s.username,s.display_name,s.score,row_number() over(order by s.score desc,s.username)::bigint
 from scored s order by s.score desc,s.username limit 100;
end $$;
revoke all on function public.start_learning_assessment(),public.submit_learning_assessment(uuid,jsonb) from public,anon;
grant execute on function public.start_learning_assessment(),public.submit_learning_assessment(uuid,jsonb) to authenticated;
revoke all on function public.get_learning_leaderboard(text,boolean) from public;
grant execute on function public.get_learning_leaderboard(text,boolean) to anon,authenticated;
