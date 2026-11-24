-- Phase 3: player-created stages, moderation queue, reports, favorites, and reviews.
create table public.custom_stages (
  id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check(char_length(title) between 3 and 60), description text not null default '' check(char_length(description)<=500),
  category text not null check(category in ('alfabeto','palabras','frases','vocabulario')),
  difficulty smallint not null check(difficulty between 1 and 5),
  status text not null default 'draft' check(status in ('draft','pending_review','published','rejected')),
  moderation_note text, play_count bigint not null default 0 check(play_count>=0), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), reviewed_at timestamptz
);
create table public.stage_levels (
  id uuid primary key default gen_random_uuid(), stage_id uuid not null references public.custom_stages(id) on delete cascade,
  order_index smallint not null check(order_index between 1 and 10), title text not null check(char_length(title) between 1 and 60),
  prompts text[] not null check(cardinality(prompts) between 2 and 20), unique(stage_id,order_index)
);
create index custom_stages_explorer_idx on public.custom_stages(status,created_at desc);
create table public.moderators(user_id uuid primary key references public.profiles(id) on delete cascade,added_at timestamptz not null default now());
create table public.stage_reports(
  id bigint generated always as identity primary key,stage_id uuid not null references public.custom_stages(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check(reason in ('inaccurate','inappropriate','spam','copyright','other')),
  details text not null default '' check(char_length(details)<=500),created_at timestamptz not null default now(),unique(stage_id,reporter_id)
);
create table public.stage_attempts(stage_id uuid not null references public.custom_stages(id) on delete cascade,player_id uuid not null references public.profiles(id) on delete cascade,completed_at timestamptz not null default now(),primary key(stage_id,player_id));
create table public.stage_reviews(stage_id uuid not null references public.custom_stages(id) on delete cascade,reviewer_id uuid not null references public.profiles(id) on delete cascade,rating smallint not null check(rating between 1 and 5),created_at timestamptz not null default now(),primary key(stage_id,reviewer_id));
create table public.stage_favorites(stage_id uuid not null references public.custom_stages(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,created_at timestamptz not null default now(),primary key(stage_id,user_id));

alter table public.custom_stages enable row level security;
alter table public.stage_levels enable row level security;
alter table public.moderators enable row level security;
alter table public.stage_reports enable row level security;
alter table public.stage_attempts enable row level security;
alter table public.stage_reviews enable row level security;
alter table public.stage_favorites enable row level security;
revoke all on public.custom_stages,public.stage_levels,public.moderators,public.stage_reports,public.stage_attempts,public.stage_reviews,public.stage_favorites from anon,authenticated;
grant select on public.custom_stages,public.stage_levels,public.stage_reviews to anon,authenticated;
grant select,insert,update on public.custom_stages,public.stage_levels to authenticated;
grant select,insert on public.stage_reports to authenticated;
grant select on public.stage_attempts,public.stage_favorites to authenticated;
grant select,insert,update on public.stage_reviews to authenticated;
create policy "Published stages or own drafts" on public.custom_stages for select using(status='published' or (select auth.uid())=author_id);
create policy "Published stage levels or own drafts" on public.stage_levels for select using(exists(select 1 from public.custom_stages s where s.id=stage_id and (s.status='published' or s.author_id=(select auth.uid()))));
create policy "Players create their drafts" on public.custom_stages for insert to authenticated with check(author_id=(select auth.uid()) and status='draft');
create policy "Players edit their drafts" on public.custom_stages for update to authenticated using(author_id=(select auth.uid()) and status in ('draft','rejected')) with check(author_id=(select auth.uid()) and status in ('draft','rejected'));
create policy "Players add levels to their drafts" on public.stage_levels for insert to authenticated with check(exists(select 1 from public.custom_stages s where s.id=stage_id and s.author_id=(select auth.uid()) and s.status in ('draft','rejected')));
create policy "Players edit levels in their drafts" on public.stage_levels for update to authenticated using(exists(select 1 from public.custom_stages s where s.id=stage_id and s.author_id=(select auth.uid()) and s.status in ('draft','rejected'))) with check(exists(select 1 from public.custom_stages s where s.id=stage_id and s.author_id=(select auth.uid()) and s.status in ('draft','rejected')));
create policy "Players read own reports" on public.stage_reports for select to authenticated using(reporter_id=(select auth.uid()));
create policy "Players submit reports" on public.stage_reports for insert to authenticated with check(reporter_id=(select auth.uid()));
create policy "Players read reviews" on public.stage_reviews for select using(true);
create policy "Players add reviews after a completion" on public.stage_reviews for insert to authenticated with check(reviewer_id=(select auth.uid()) and exists(select 1 from public.stage_attempts a where a.stage_id=stage_reviews.stage_id and a.player_id=(select auth.uid())));
create policy "Players edit their reviews" on public.stage_reviews for update to authenticated using(reviewer_id=(select auth.uid()) and exists(select 1 from public.stage_attempts a where a.stage_id=stage_reviews.stage_id and a.player_id=(select auth.uid()))) with check(reviewer_id=(select auth.uid()));
create policy "Players read own favorites" on public.stage_favorites for select to authenticated using(user_id=(select auth.uid()));

create or replace function public.create_draft_stage(p_title text,p_description text,p_category text,p_difficulty smallint,p_prompts text[])
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); sid uuid;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if p_title is null or char_length(trim(p_title)) not between 3 and 60 then raise exception 'Title must contain 3–60 characters'; end if;
 if char_length(coalesce(p_description,''))>500 then raise exception 'Description is too long'; end if;
 if p_category not in ('alfabeto','palabras','frases','vocabulario') or p_difficulty not between 1 and 5 then raise exception 'Invalid stage settings'; end if;
 if p_prompts is null or cardinality(p_prompts) not between 2 and 20 then raise exception 'Provide 2–20 prompts'; end if;
 if exists(select 1 from unnest(p_prompts) x where char_length(trim(x)) not between 1 and 80 or x ~* '<|>|https?://|www\.') then raise exception 'A prompt is empty, too long, or contains markup or a link'; end if;
 insert into public.custom_stages(author_id,title,description,category,difficulty) values(actor,trim(p_title),coalesce(trim(p_description),''),p_category,p_difficulty) returning id into sid;
 insert into public.stage_levels(stage_id,order_index,title,prompts) values(sid,1,'Etapa inicial',p_prompts);
 return sid;
end $$;
create or replace function public.submit_stage_for_review(p_stage_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); stage public.custom_stages%rowtype;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select * into stage from public.custom_stages where id=p_stage_id and author_id=actor for update;
 if not found then raise exception 'Stage not found'; end if;
 if stage.status not in ('draft','rejected') then raise exception 'Stage is already under review or published'; end if;
 if not exists(select 1 from public.stage_levels where stage_id=p_stage_id) then raise exception 'Add a level first'; end if;
 if stage.title ~* '<|>|https?://|www\.' or stage.description ~* '<|>|https?://|www\.' then raise exception 'Remove markup and links before submission'; end if;
 update public.custom_stages set status='pending_review',moderation_note=null,updated_at=now() where id=p_stage_id;
 return 'pending_review';
end $$;
create or replace function public.moderate_stage(p_stage_id uuid,p_approved boolean,p_note text default '')
returns text language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_status text;
begin
 if actor is null or not exists(select 1 from public.moderators where user_id=actor) then raise exception 'Moderator role required'; end if;
 if char_length(coalesce(p_note,''))>500 then raise exception 'Note is too long'; end if;
 target_status:=case when p_approved then 'published' else 'rejected' end;
 update public.custom_stages set status=target_status,moderation_note=nullif(trim(p_note),''),reviewed_at=now(),updated_at=now() where id=p_stage_id and status='pending_review';
 if not found then raise exception 'Stage is not awaiting review'; end if;
 return target_status;
end $$;
create or replace function public.report_stage(p_stage_id uuid,p_reason text,p_details text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if p_reason not in ('inaccurate','inappropriate','spam','copyright','other') then raise exception 'Invalid report reason'; end if;
 insert into public.stage_reports(stage_id,reporter_id,reason,details) values(p_stage_id,actor,p_reason,left(coalesce(p_details,''),500)) on conflict(stage_id,reporter_id) do nothing;
end $$;
create or replace function public.record_stage_completion(p_stage_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.custom_stages where id=p_stage_id and status='published') then raise exception 'Stage is not available'; end if;
 insert into public.stage_attempts(stage_id,player_id) values(p_stage_id,actor) on conflict do nothing;
 if found then update public.custom_stages set play_count=play_count+1 where id=p_stage_id; end if;
end $$;
create or replace function public.review_stage(p_stage_id uuid,p_rating smallint)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if p_rating not between 1 and 5 then raise exception 'Rating must be 1–5'; end if;
 if not exists(select 1 from public.stage_attempts where stage_id=p_stage_id and player_id=actor) then raise exception 'Complete the stage before reviewing it'; end if;
 insert into public.stage_reviews(stage_id,reviewer_id,rating) values(p_stage_id,actor,p_rating)
 on conflict(stage_id,reviewer_id) do update set rating=excluded.rating,created_at=now();
end $$;
create or replace function public.toggle_stage_favorite(p_stage_id uuid,p_favorite boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if p_favorite then insert into public.stage_favorites(stage_id,user_id) values(p_stage_id,actor) on conflict do nothing;
 else delete from public.stage_favorites where stage_id=p_stage_id and user_id=actor; end if;
end $$;
create or replace function public.get_moderation_queue()
returns table(stage_id uuid,title text,description text,author_username text,created_at timestamptz,report_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not exists(select 1 from public.moderators where user_id=actor) then raise exception 'Moderator role required'; end if;
 return query select s.id,s.title,s.description,p.username,s.created_at,count(r.id)
 from public.custom_stages s join public.profiles p on p.id=s.author_id left join public.stage_reports r on r.stage_id=s.id
 where s.status='pending_review' group by s.id,p.username order by s.created_at asc;
end $$;

revoke all on function public.create_draft_stage(text,text,text,smallint,text[]),public.submit_stage_for_review(uuid),
 public.moderate_stage(uuid,boolean,text),public.report_stage(uuid,text,text),public.record_stage_completion(uuid),
 public.review_stage(uuid,smallint),public.toggle_stage_favorite(uuid,boolean),public.get_moderation_queue() from public,anon;
grant execute on function public.create_draft_stage(text,text,text,smallint,text[]),public.submit_stage_for_review(uuid),
 public.moderate_stage(uuid,boolean,text),public.report_stage(uuid,text,text),public.record_stage_completion(uuid),
 public.review_stage(uuid,smallint),public.toggle_stage_favorite(uuid,boolean),public.get_moderation_queue() to authenticated;
create or replace function public.get_moderation_queue()
returns table(stage_id uuid,title text,description text,author_username text,created_at timestamptz,report_count bigint,prompts text[],report_summary text)
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not exists(select 1 from public.moderators where user_id=actor) then raise exception 'Moderator role required'; end if;
 return query
 select s.id,s.title,s.description,p.username,s.created_at,
   (select count(*) from public.stage_reports r where r.stage_id=s.id),
   coalesce((select array_agg(prompt) from public.stage_levels l cross join lateral unnest(l.prompts) prompt where l.stage_id=s.id),'{}'::text[]),
   coalesce((select string_agg(r.reason||': '||r.details,E'\n') from public.stage_reports r where r.stage_id=s.id),'')
 from public.custom_stages s join public.profiles p on p.id=s.author_id
 where s.status='pending_review' or exists(select 1 from public.stage_reports r where r.stage_id=s.id)
 order by s.created_at asc;
end $$;
revoke all on function public.get_moderation_queue() from public,anon;
grant execute on function public.get_moderation_queue() to authenticated;
