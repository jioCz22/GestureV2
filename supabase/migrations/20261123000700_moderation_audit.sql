-- Phase 3: auditable moderation actions.
create table public.moderation_actions(
 id bigint generated always as identity primary key,
 stage_id uuid not null references public.custom_stages(id) on delete cascade,
 moderator_id uuid not null references public.profiles(id) on delete cascade,
 action text not null check(action in ('approved','rejected','suspended')),
 note text not null default '',created_at timestamptz not null default now()
);
alter table public.moderation_actions enable row level security;
revoke all on public.moderation_actions from anon,authenticated;
create or replace function public.moderate_stage(p_stage_id uuid,p_approved boolean,p_note text default '')
returns text language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_status text;
begin
 if actor is null or not exists(select 1 from public.moderators where user_id=actor) then raise exception 'Moderator role required'; end if;
 if char_length(coalesce(p_note,''))>500 then raise exception 'Note is too long'; end if;
 target_status:=case when p_approved then 'published' else 'rejected' end;
 update public.custom_stages set status=target_status,moderation_note=nullif(trim(p_note),''),reviewed_at=now(),updated_at=now()
 where id=p_stage_id and status='pending_review';
 if not found then raise exception 'Stage is not awaiting review'; end if;
 insert into public.moderation_actions(stage_id,moderator_id,action,note)
 values(p_stage_id,actor,target_status,coalesce(trim(p_note),''));
 return target_status;
end $$;
revoke all on function public.moderate_stage(uuid,boolean,text) from public,anon;
grant execute on function public.moderate_stage(uuid,boolean,text) to authenticated;


