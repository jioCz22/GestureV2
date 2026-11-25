-- Private, server-scored assessment sessions. Correct targets stay in private session JSON.
create table public.player_assessment_sessions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 questions jsonb not null check(jsonb_typeof(questions)='array'),
 started_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '10 minutes', submitted_at timestamptz
);
create table public.player_assessment_scores (
 session_id uuid primary key references public.player_assessment_sessions(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 correct integer not null check(correct>=0), total integer not null check(total>0),
 accuracy_percent smallint not null check(accuracy_percent between 0 and 100), created_at timestamptz not null default now()
);
create table public.assessment_usage(user_id uuid not null references public.profiles(id) on delete cascade, usage_day date not null, attempt_count smallint not null check(attempt_count between 1 and 10), primary key(user_id,usage_day));
create table public.assessment_assets(activity_id text primary key references public.activity_catalog(activity_id) on delete cascade, asset_token text not null unique check(asset_token ~ '^[a-f0-9]{32}$'));
insert into public.assessment_assets(activity_id,asset_token) values  ('letter:A','6b5a63a3d4ba468bb321401d74e6cc71'),
  ('letter:B','7be0d8aa3f0541faa946d42588625857'),
  ('letter:C','7d6249a79cd44c90b73b39c9c0e24fd4'),
  ('letter:D','2124a19b21114d69af68ccb7e2490229'),
  ('letter:E','1b5edda0406f45f18cf123dd007d6b17'),
  ('letter:F','f185807c9aa149e08f855c78434f728c'),
  ('letter:G','b81610c44d634a4fa8724905cf86740f'),
  ('letter:H','3e80a0f5a50447968d34da4116c6ff45'),
  ('letter:I','ee4721ebfc364d4c8b9d2a70633f66b5'),
  ('letter:J','f5396cb8b1854497b92538986a068055'),
  ('letter:K','dc7872fed4954edf87f1bbaf1421c5c7'),
  ('letter:L','b70530193d2846929d7d512121265964'),
  ('letter:M','2c44f2b10adf408ab36257c4d5821927'),
  ('letter:N','9363dac336e34c0eb417bf2ee60bba68'),
  ('letter:O','c6bf071e63f948629c33854314891f66'),
  ('letter:P','2ad2d237ea4c44b0b07c54bc67192045'),
  ('letter:Q','97aa2dd4d56a4f8ca586565d44d59b2b'),
  ('letter:R','c5d66d6f4d72417584bb648ef6036223'),
  ('letter:S','7f05c96af93f4a189627882821fa2df9'),
  ('letter:T','5f2c8fadb4804288b48467b4e4795620'),
  ('letter:U','5a63ffcacc3544aa91ed2634ecbc0a17'),
  ('letter:V','c8c72c3e645e4dc9b01b20143541821c'),
  ('letter:W','3701e40a0e824f31a7b90c9e1726580f'),
  ('letter:X','482bc2d3a96f447cb51274a3e7a92b56'),
  ('letter:Y','75c582684982488a9439077f8e3996f7'),
  ('letter:Z','2fed5b15563d4fb4a931c25750ef4031')
on conflict(activity_id) do nothing;
alter table public.player_assessment_sessions enable row level security;
alter table public.player_assessment_scores enable row level security;
alter table public.assessment_usage enable row level security;
alter table public.assessment_assets enable row level security;
revoke all on public.player_assessment_sessions,public.player_assessment_scores,public.assessment_usage,public.assessment_assets from anon,authenticated;
create policy "Players read own assessment scores" on public.player_assessment_scores for select to authenticated using((select auth.uid())=user_id);
grant select on public.player_assessment_scores to authenticated;
create or replace function public.start_learning_assessment()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); used smallint; sid uuid; private_q jsonb; public_q jsonb; day_utc date:=(now() at time zone 'UTC')::date;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 insert into public.assessment_usage as au(user_id,usage_day,attempt_count) values(actor,day_utc,1)
 on conflict(user_id,usage_day) do update set attempt_count=au.attempt_count+1 where au.attempt_count<10 returning attempt_count into used;
 if not found then raise exception 'Daily assessment limit reached'; end if;
 select jsonb_agg(jsonb_build_object('id',x.qid,'target',x.target,'asset_token',x.token,'choices',x.choices) order by x.n) into private_q
 from (select row_number() over() n,gen_random_uuid()::text qid,c.activity_key target,a.asset_token token,
  (select jsonb_agg(z.choice order by random()) from unnest(array_append(array(select cc.activity_key from public.activity_catalog cc where cc.activity_type='letter' and cc.activity_key<>c.activity_key order by random() limit 3),c.activity_key)) z(choice)) choices
  from (select activity_id,activity_key from public.activity_catalog where activity_type='letter' order by random() limit 10) c join public.assessment_assets a using(activity_id)) x;
 if jsonb_array_length(coalesce(private_q,'[]'::jsonb))<>10 then raise exception 'Assessment content is incomplete'; end if;
 select jsonb_agg(jsonb_build_object('id',q->>'id','asset_token',q->>'asset_token','choices',q->'choices') order by ord) into public_q from jsonb_array_elements(private_q) with ordinality e(q,ord);
 insert into public.player_assessment_sessions(user_id,questions) values(actor,private_q) returning id into sid;
 return jsonb_build_object('session_id',sid,'questions',public_q,'expires_at',now()+interval '10 minutes');
end $$;
create or replace function public.submit_learning_assessment(p_session_id uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); sess public.player_assessment_sessions%rowtype; total_n integer; correct_n integer; accuracy smallint;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if jsonb_typeof(p_answers)<>'array' then raise exception 'Answers must be an array'; end if;
 select * into sess from public.player_assessment_sessions where id=p_session_id and user_id=actor for update;
 if not found or sess.expires_at<now() or sess.submitted_at is not null then raise exception 'Assessment expired or already submitted'; end if;
 total_n:=jsonb_array_length(sess.questions);
 if jsonb_array_length(p_answers)<>total_n then raise exception 'Answer every question exactly once'; end if;
 if exists(select 1 from jsonb_array_elements(p_answers) a group by a->>'id' having count(*)>1) or exists(select 1 from jsonb_array_elements(p_answers) a where not exists(select 1 from jsonb_array_elements(sess.questions) q where q->>'id'=a->>'id')) then raise exception 'Invalid answer set'; end if;
 select count(*) into correct_n from jsonb_array_elements(sess.questions) q where exists(select 1 from jsonb_array_elements(p_answers) a where a->>'id'=q->>'id' and a->>'answer'=q->>'target');
 accuracy:=round(correct_n*100.0/total_n)::smallint;
 update public.player_assessment_sessions set submitted_at=now() where id=p_session_id;
 insert into public.player_assessment_scores values(p_session_id,actor,correct_n,total_n,accuracy,now());
 return jsonb_build_object('correct',correct_n,'total',total_n,'accuracy_percent',accuracy);
end $$;
create or replace function public.get_learning_leaderboard(p_metric text default 'experience',p_weekly boolean default false)
returns table(username text,display_name text,score bigint,"position" bigint)
begin
 if p_metric not in ('experience','mastery','consistency','weekly_activity','precision') then raise exception 'Unknown ranking metric'; end if;
 return query with v as (select p.id,p.username,p.display_name,coalesce(w.verified_xp_total,0) xp,
 (select count(*) from public.experience_transactions e where e.user_id=p.id and e.verified) completed,
 (select count(distinct (e.created_at at time zone 'UTC')::date) from public.experience_transactions e where e.user_id=p.id and e.verified and e.created_at>=now()-case when p_weekly then interval '7 days' else interval '30 days' end) days,
 (select count(*) from public.experience_transactions e where e.user_id=p.id and e.verified and e.created_at>=now()-interval '7 days') weekly,
 (select coalesce(sum(e.amount),0) from public.experience_transactions e where e.user_id=p.id and e.verified and e.created_at>=now()-interval '7 days') weekly_xp,
 (select coalesce(round(avg(a.accuracy_percent)),0) from public.player_assessment_scores a where a.user_id=p.id and (not p_weekly or a.created_at>=now()-interval '7 days')) precision
 from public.profiles p join public.player_settings ps on ps.user_id=p.id and ps.show_profile and ps.show_xp left join public.player_wallets w on w.user_id=p.id), s as (select username,display_name,case p_metric when 'experience' then case when p_weekly then weekly_xp else xp end when 'mastery' then completed when 'consistency' then days when 'weekly_activity' then weekly when 'precision' then precision end::bigint score from v)
 select s.username,s.display_name,s.score,row_number() over(order by s.score desc,s.username)::bigint from s order by s.score desc,s.username limit 100;
end $$;
revoke all on function public.start_learning_assessment(),public.submit_learning_assessment(uuid,jsonb),public.get_learning_leaderboard(text,boolean) from public,anon,authenticated;
grant execute on function public.start_learning_assessment(),public.submit_learning_assessment(uuid,jsonb) to authenticated;
grant execute on function public.get_learning_leaderboard(text,boolean) to anon,authenticated;

