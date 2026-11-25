-- Phase 1b final local hardening: explicit client RPC allow-list and moderation suspension.
-- No remote project is linked by this migration.

-- Direct table access is deliberately limited. All sensitive reads go through projections.
revoke all on all tables in schema public from anon, authenticated;
grant select,insert,update,delete on public.player_progress to authenticated;
grant select on public.avatar_items to anon,authenticated;
grant select on public.player_inventory,public.player_avatar,public.player_achievements,public.player_assessment_scores to authenticated;
grant select,update on public.player_settings to authenticated;

-- Remove implicit PUBLIC execution from every application function. Trigger functions
-- remain callable by triggers; they are not exposed to API roles.
do $$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'
 loop execute format('revoke all on function %s from public, anon, authenticated',f.signature); end loop;
end $$;

do $$
declare signature text;
begin
 foreach signature in array array[
  'public.get_public_profile(text)','public.get_learning_leaderboard(text,boolean)','public.get_public_stage_cards(text,smallint,uuid[],text)',
  'public.get_my_v2_profile()','public.equip_avatar_item(text)',
  'public.get_daily_mission_status()','public.get_creator_stats()',
  'public.create_draft_stage(text,text,text,smallint,text[])','public.submit_stage_for_review(uuid)','public.moderate_stage(uuid,boolean,text)',
  'public.save_draft_stage_level(uuid,smallint,text,text[])',
  'public.report_stage(uuid,text,text)','public.record_stage_completion(uuid)','public.review_stage(uuid,smallint)','public.toggle_stage_favorite(uuid,boolean)',
  'public.get_moderation_queue()','public.get_my_favorite_stage_cards()','public.get_my_stages()','public.get_my_challenges()',
  'public.create_player_challenge(text,text[])','public.join_player_challenge(text)','public.complete_player_challenge(uuid)',
  'public.start_learning_assessment()','public.submit_learning_assessment(uuid,jsonb)'
 ] loop
  if to_regprocedure(signature) is not null then execute format('grant execute on function %s to authenticated',signature); end if;
 end loop;
 foreach signature in array array['public.get_public_profile(text)','public.get_learning_leaderboard(text,boolean)','public.get_public_stage_cards(text,smallint,uuid[],text)'] loop
  if to_regprocedure(signature) is not null then execute format('grant execute on function %s to anon, authenticated',signature); end if;
 end loop;
end $$;

-- These routines remain in the schema for compatibility but cannot be called by
-- browser roles until a trusted server-side reward validator is deployed.
revoke all on function public.claim_learning_completion(text,text),public.claim_daily_mission(),public.purchase_avatar_item(text)
 from public,anon,authenticated;

-- Add or edit levels only while the parent stage is editable. Orders must remain
-- contiguous; direct table writes are revoked from browser roles below.
create or replace function public.save_draft_stage_level(p_stage_id uuid,p_order_index smallint,p_title text,p_prompts text[])
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); parent public.custom_stages%rowtype; level_id uuid;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select * into parent from public.custom_stages where id=p_stage_id and author_id=actor for update;
 if not found or parent.status not in ('draft','rejected') then raise exception 'Editable draft not found'; end if;
 if p_order_index not between 1 and 20 then raise exception 'Level order must be 1–20'; end if;
 if p_title is null or char_length(trim(p_title)) not between 1 and 60 then raise exception 'Level title must contain 1–60 characters'; end if;
 if p_prompts is null or cardinality(p_prompts) not between 2 and 20 then raise exception 'Provide 2–20 prompts'; end if;
 if exists(select 1 from unnest(p_prompts) x where x is null or char_length(trim(x)) not between 1 and 80 or x ~* '<|>|https?://|www\.') then raise exception 'A prompt is empty, too long, or contains markup or a link'; end if;
 if not exists(select 1 from public.stage_levels where stage_id=p_stage_id and order_index=p_order_index)
    and p_order_index<>(coalesce((select max(order_index) from public.stage_levels where stage_id=p_stage_id),0)+1) then
   raise exception 'Levels must be added in order without gaps';
 end if;
 insert into public.stage_levels(stage_id,order_index,title,prompts) values(p_stage_id,p_order_index,trim(p_title),p_prompts)
 on conflict(stage_id,order_index) do update set title=excluded.title,prompts=excluded.prompts returning id into level_id;
 update public.custom_stages set updated_at=now() where id=p_stage_id;
 return level_id;
end $$;
revoke all on function public.save_draft_stage_level(uuid,smallint,text,text[]) from public,anon,authenticated;
grant execute on function public.save_draft_stage_level(uuid,smallint,text,text[]) to authenticated;

-- Client requests are not evidence that a published community stage was completed.
-- Keep the RPC callable for a clear, safe failure until server-side validation exists.
create or replace function public.record_stage_completion(p_stage_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 raise exception 'Stage completion requires server validation';
end $$;

-- Profile rows are never directly readable or mutable by browser clients.
revoke all on public.profiles from anon,authenticated;
drop policy if exists "Players can view their own profile row" on public.profiles;

-- Content already approved can be removed from public discovery after a valid report
-- and moderator action; original data and audit history remain intact.
alter table public.custom_stages drop constraint if exists custom_stages_status_check;
alter table public.custom_stages add constraint custom_stages_status_check check(status in ('draft','pending_review','published','rejected','suspended'));
create or replace function public.suspend_reported_stage(p_stage_id uuid,p_note text default '')
returns text language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not exists(select 1 from public.moderators where user_id=actor) then raise exception 'Moderator role required'; end if;
 if char_length(coalesce(p_note,''))>500 then raise exception 'Note is too long'; end if;
 if not exists(select 1 from public.stage_reports where stage_id=p_stage_id) then raise exception 'A report is required'; end if;
 update public.custom_stages set status='suspended',moderation_note=nullif(trim(p_note),''),reviewed_at=now(),updated_at=now()
 where id=p_stage_id and status='published';
 if not found then raise exception 'Published stage not found'; end if;
 insert into public.moderation_actions(stage_id,moderator_id,action,note) values(p_stage_id,actor,'suspended',coalesce(trim(p_note),''));
 return 'suspended';
end $$;
revoke all on function public.suspend_reported_stage(uuid,text) from public,anon,authenticated;
grant execute on function public.suspend_reported_stage(uuid,text) to authenticated;

