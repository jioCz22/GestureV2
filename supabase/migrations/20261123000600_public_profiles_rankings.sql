-- Phase 3: public profile reads and privacy-aware learning leaderboards.
create or replace function public.get_public_profile(p_username text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare target public.profiles%rowtype; settings public.player_settings%rowtype; xp bigint; stage_count bigint; published_count bigint; activity jsonb:='[]'::jsonb;
begin
 select * into target from public.profiles where lower(username)=lower(trim(p_username));
 if not found or not public.is_profile_public(target.id) then return null; end if;
 select * into settings from public.player_settings where user_id=target.id;
 select coalesce(xp_total,0) into xp from public.player_wallets where user_id=target.id;
 select count(*),count(*) filter(where status='published') into stage_count,published_count from public.custom_stages where author_id=target.id;
 if coalesce(settings.show_activity,false) then
   select coalesce(jsonb_agg(jsonb_build_object('type',recent.activity_type,'activity',recent.activity_key,'completed_at',recent.created_at) order by recent.created_at desc),'[]'::jsonb)
   into activity from (select c.activity_type,c.activity_key,e.created_at from public.experience_transactions e join public.activity_catalog c on c.activity_id=e.activity_id
     where e.user_id=target.id order by e.created_at desc limit 10) recent;
 end if;
 return jsonb_build_object('username',target.username,'display_name',target.display_name,'avatar_url',target.avatar_url,
   'created_at',target.created_at,'xp_total',case when coalesce(settings.show_xp,true) then coalesce(xp,0) else null end,
   'stages_created',stage_count,'stages_published',published_count,'recent_activity',activity);
end $$;
create or replace function public.get_learning_leaderboard(p_metric text default 'experience',p_weekly boolean default false)
returns table(username text,display_name text,score bigint,position bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
 if p_metric not in ('experience','mastery','consistency','weekly_activity') then raise exception 'Unknown ranking metric'; end if;
 return query
 with visible as (
  select p.id,p.username,p.display_name,coalesce(w.xp_total,0) xp_total,
   (select count(*) from public.experience_transactions e where e.user_id=p.id) completed,
   (select count(distinct (e.created_at at time zone 'UTC')::date) from public.experience_transactions e where e.user_id=p.id and e.created_at>=now()-case when p_weekly then interval '7 days' else interval '30 days' end) active_days,
   (select count(*) from public.experience_transactions e where e.user_id=p.id and e.created_at>=now()-interval '7 days') weekly_count,
   (select coalesce(sum(e.amount),0) from public.experience_transactions e where e.user_id=p.id and e.created_at>=now()-interval '7 days') weekly_xp
  from public.profiles p join public.player_settings ps on ps.user_id=p.id and ps.show_profile and ps.show_xp
  left join public.player_wallets w on w.user_id=p.id
 ), scored as (
  select v.username,v.display_name,case p_metric when 'experience' then case when p_weekly then v.weekly_xp else v.xp_total end
    when 'mastery' then v.completed when 'consistency' then v.active_days when 'weekly_activity' then v.weekly_count end::bigint score
  from visible v
 ) select s.username,s.display_name,s.score,row_number() over(order by s.score desc,s.username)::bigint
 from scored s order by s.score desc,s.username limit 100;
end $$;
revoke all on function public.get_public_profile(text),public.get_learning_leaderboard(text,boolean) from public;
grant execute on function public.get_public_profile(text),public.get_learning_leaderboard(text,boolean) to anon,authenticated;


