-- Phase 2: private wallets, auditable reward ledgers, missions, and avatar inventory.

create table public.player_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  show_profile boolean not null default true,
  show_xp boolean not null default true,
  show_activity boolean not null default false,
  updated_at timestamptz not null default now()
);
create or replace function public.is_profile_public(profile_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select ps.show_profile from public.player_settings ps where ps.user_id=profile_id),true)
$$;
drop policy if exists "Public profiles are viewable" on public.profiles;
create policy "Visible profiles are viewable" on public.profiles for select
  using((select auth.uid())=id or public.is_profile_public(id));
alter table public.player_settings enable row level security;
revoke all on public.player_settings from anon,authenticated;
grant select,update on public.player_settings to authenticated;
create policy "Players read own settings" on public.player_settings for select to authenticated using((select auth.uid())=user_id);
create policy "Players update own settings" on public.player_settings for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);

create table public.player_wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  xp_total bigint not null default 0 check(xp_total>=0),
  coin_balance bigint not null default 0 check(coin_balance>=0),
  updated_at timestamptz not null default now()
);
create table public.activity_catalog (
  activity_id text primary key,
  activity_type text not null check(activity_type in ('letter','word','phrase')),
  activity_key text not null,
  xp_reward integer not null check(xp_reward between 1 and 100),
  coin_reward integer not null check(coin_reward between 0 and 20),
  unique(activity_type,activity_key)
);
create table public.experience_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  activity_id text not null references public.activity_catalog(activity_id),
  amount integer not null check(amount>0),
  created_at timestamptz not null default now(),
  unique(user_id,activity_id)
);
create table public.coin_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  idempotency_key text not null,
  amount integer not null check(amount<>0),
  reason text not null check(reason in ('activity','daily_mission','purchase','moderation_reward')),
  created_at timestamptz not null default now(),
  unique(user_id,idempotency_key)
);
insert into public.activity_catalog values
('letter:A','letter','A',10,2),('letter:B','letter','B',10,2),('letter:C','letter','C',10,2),('letter:D','letter','D',10,2),('letter:E','letter','E',10,2),('letter:F','letter','F',10,2),('letter:G','letter','G',10,2),('letter:H','letter','H',10,2),('letter:I','letter','I',10,2),('letter:J','letter','J',10,2),('letter:K','letter','K',10,2),('letter:L','letter','L',10,2),('letter:M','letter','M',10,2),('letter:N','letter','N',10,2),('letter:O','letter','O',10,2),('letter:P','letter','P',10,2),('letter:Q','letter','Q',10,2),('letter:R','letter','R',10,2),('letter:S','letter','S',10,2),('letter:T','letter','T',10,2),('letter:U','letter','U',10,2),('letter:V','letter','V',10,2),('letter:W','letter','W',10,2),('letter:X','letter','X',10,2),('letter:Y','letter','Y',10,2),('letter:Z','letter','Z',10,2),
('word:HOLA','word','HOLA',15,3),('word:CASA','word','CASA',15,3),('word:MESA','word','MESA',15,3),('word:LUNA','word','LUNA',15,3),('word:GATO','word','GATO',15,3),('word:GRACIAS','word','GRACIAS',15,3),('word:AMIGO','word','AMIGO',15,3),('word:FAMILIA','word','FAMILIA',15,3),('word:AGUA','word','AGUA',15,3),('word:COMIDA','word','COMIDA',15,3),('word:AMOR','word','AMOR',15,3),('word:FELIZ','word','FELIZ',15,3),('word:PERSONA','word','PERSONA',15,3),('word:MADRE','word','MADRE',15,3),('word:PADRE','word','PADRE',15,3),('word:ESCUELA','word','ESCUELA',15,3),('word:TRABAJO','word','TRABAJO',15,3),('word:LIBRO','word','LIBRO',15,3),('word:AMISTAD','word','AMISTAD',15,3),('word:MUNDO','word','MUNDO',15,3),('word:TECNOLOGIA','word','TECNOLOGIA',15,3),('word:APRENDER','word','APRENDER',15,3),('word:COMUNICACION','word','COMUNICACION',15,3),('word:CONOCIMIENTO','word','CONOCIMIENTO',15,3),('word:DESARROLLO','word','DESARROLLO',15,3)
on conflict(activity_id) do nothing;

create table public.avatar_items (
  id uuid primary key default gen_random_uuid(),
  item_key text not null unique check(item_key ~ '^[a-z0-9_]{2,40}$'),
  category text not null check(category in ('skin','hair','top','bottom','shoes','accessory','background')),
  display_name text not null,
  color_hex text not null check(color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  icon text not null default '', price integer not null default 0 check(price>=0),
  is_starter boolean not null default false, active boolean not null default true
);
create table public.player_inventory (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_id uuid not null references public.avatar_items(id) on delete restrict,
  acquired_at timestamptz not null default now(), primary key(user_id,item_id)
);
create table public.player_avatar (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  equipped_items jsonb not null default '{}'::jsonb check(jsonb_typeof(equipped_items)='object'),
  updated_at timestamptz not null default now()
);
insert into public.avatar_items(item_key,category,display_name,color_hex,icon,price,is_starter) values
('skin_sand','skin','Arena cálida','#D9A27D','',0,true),('skin_olive','skin','Oliva','#A96F52','',0,false),('skin_deep','skin','Cacao','#704735','',0,false),
('hair_midnight','hair','Cabello oscuro','#27223A','✦',0,true),('hair_copper','hair','Cobre','#B95F3B','✦',80,false),('hair_violet','hair','Violeta','#7856C7','✦',110,false),
('top_sky','top','Playera cielo','#4D9CDA','',0,true),('top_coral','top','Sudadera coral','#E87567','',100,false),('top_lime','top','Chaqueta lima','#86B95A','',120,false),
('bottom_ink','bottom','Pantalón tinta','#343B63','',0,true),('bottom_denim','bottom','Mezclilla','#5478A5','',70,false),
('shoes_cloud','shoes','Tenis nube','#E8ECFA','',0,true),('shoes_sun','shoes','Tenis sol','#F3BA45','',60,false),
('accessory_none','accessory','Sin accesorio','#FFFFFF','',0,true),('accessory_glasses','accessory','Lentes redondos','#34304D','◉',90,false),
('background_dusk','background','Atardecer','#7255B9','',0,true),('background_mint','background','Menta','#59A890','',75,false)
on conflict(item_key) do nothing;
create table public.player_achievements(user_id uuid not null references public.profiles(id) on delete cascade,achievement_key text not null,earned_at timestamptz not null default now(),primary key(user_id,achievement_key));
create table public.mission_claims(user_id uuid not null references public.profiles(id) on delete cascade,mission_key text not null,period_start date not null,claimed_at timestamptz not null default now(),primary key(user_id,mission_key,period_start));

create or replace function public.initialize_player_v2() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.player_settings(user_id) values(new.id) on conflict do nothing;
  insert into public.player_wallets(user_id) values(new.id) on conflict do nothing;
  insert into public.player_avatar(user_id) values(new.id) on conflict do nothing;
  insert into public.player_inventory(user_id,item_id) select new.id,id from public.avatar_items where is_starter on conflict do nothing;
  return new;
end $$;
create trigger on_profile_created_initialize_v2 after insert on public.profiles for each row execute function public.initialize_player_v2();
insert into public.player_settings(user_id) select id from public.profiles on conflict do nothing;
insert into public.player_wallets(user_id) select id from public.profiles on conflict do nothing;
insert into public.player_avatar(user_id) select id from public.profiles on conflict do nothing;
insert into public.player_inventory(user_id,item_id) select p.id,a.id from public.profiles p cross join public.avatar_items a where a.is_starter on conflict do nothing;

alter table public.player_settings enable row level security;
alter table public.player_wallets enable row level security;
alter table public.experience_transactions enable row level security;
alter table public.coin_transactions enable row level security;
alter table public.avatar_items enable row level security;
alter table public.player_inventory enable row level security;
alter table public.player_avatar enable row level security;
alter table public.player_achievements enable row level security;
alter table public.mission_claims enable row level security;
revoke all on public.player_wallets,public.experience_transactions,public.coin_transactions,public.player_inventory,
  public.player_avatar,public.player_achievements,public.mission_claims,public.activity_catalog from anon,authenticated;
revoke all on public.player_settings from anon,authenticated;
grant select,update on public.player_settings to authenticated;
grant select on public.avatar_items to anon,authenticated;
grant select on public.player_inventory,public.player_avatar,public.player_achievements to authenticated;
create policy "Players read own settings" on public.player_settings for select to authenticated using((select auth.uid())=user_id);
create policy "Players update own settings" on public.player_settings for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
create policy "Catalog items are public" on public.avatar_items for select using(active);
create policy "Players read own inventory" on public.player_inventory for select to authenticated using((select auth.uid())=user_id);
create policy "Players read own avatar" on public.player_avatar for select to authenticated using((select auth.uid())=user_id);
create policy "Players read own achievements" on public.player_achievements for select to authenticated using((select auth.uid())=user_id);

create or replace function public.claim_learning_completion(p_activity_type text,p_activity_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); item public.activity_catalog%rowtype; wallet public.player_wallets%rowtype; inserted_id bigint; coins integer:=0;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select * into item from public.activity_catalog where activity_type=p_activity_type and activity_key=p_activity_key;
  if not found then raise exception 'Unknown learning activity'; end if;
  insert into public.player_wallets(user_id) values(actor) on conflict do nothing;
  select * into wallet from public.player_wallets where user_id=actor for update;
  insert into public.experience_transactions(user_id,activity_id,amount) values(actor,item.activity_id,item.xp_reward)
    on conflict(user_id,activity_id) do nothing returning id into inserted_id;
  if inserted_id is null then return jsonb_build_object('awarded',false,'xp_total',wallet.xp_total,'coin_balance',wallet.coin_balance); end if;
  update public.player_wallets set xp_total=xp_total+item.xp_reward,updated_at=now() where user_id=actor returning * into wallet;
  if coalesce((select sum(amount) from public.coin_transactions where user_id=actor and amount>0 and created_at>=date_trunc('day',now())),0)+item.coin_reward<=100 and item.coin_reward>0 then
    insert into public.coin_transactions(user_id,idempotency_key,amount,reason) values(actor,'activity:'||item.activity_id,item.coin_reward,'activity') on conflict do nothing;
    if found then
      update public.player_wallets set coin_balance=coin_balance+item.coin_reward,updated_at=now() where user_id=actor returning * into wallet;
      coins:=item.coin_reward;
    end if;
  end if;
  return jsonb_build_object('awarded',true,'xp_awarded',item.xp_reward,'coins_awarded',coins,'xp_total',wallet.xp_total,'coin_balance',wallet.coin_balance);
end $$;

create or replace function public.purchase_avatar_item(p_item_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); item public.avatar_items%rowtype; wallet public.player_wallets%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select * into item from public.avatar_items where item_key=p_item_key and active;
  if not found then raise exception 'Item unavailable'; end if;
  insert into public.player_wallets(user_id) values(actor) on conflict do nothing;
  select * into wallet from public.player_wallets where user_id=actor for update;
  if exists(select 1 from public.player_inventory where user_id=actor and item_id=item.id) then raise exception 'Item already owned'; end if;
  if wallet.coin_balance<item.price then raise exception 'Not enough coins'; end if;
  if item.price>0 then
    insert into public.coin_transactions(user_id,idempotency_key,amount,reason) values(actor,'purchase:'||item.item_key,-item.price,'purchase');
    update public.player_wallets set coin_balance=coin_balance-item.price,updated_at=now() where user_id=actor returning * into wallet;
  end if;
  insert into public.player_inventory(user_id,item_id) values(actor,item.id);
  return jsonb_build_object('item_key',item.item_key,'coin_balance',wallet.coin_balance);
end $$;
create or replace function public.equip_avatar_item(p_item_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); item public.avatar_items%rowtype; equipped jsonb;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select ai.* into item from public.avatar_items ai join public.player_inventory pi on pi.item_id=ai.id where pi.user_id=actor and ai.item_key=p_item_key and ai.active;
  if not found then raise exception 'Item not owned'; end if;
  insert into public.player_avatar(user_id) values(actor) on conflict do nothing;
  update public.player_avatar set equipped_items=equipped_items||jsonb_build_object(item.category,item.item_key),updated_at=now() where user_id=actor returning equipped_items into equipped;
  return equipped;
end $$;
create or replace function public.claim_daily_mission()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); wallet public.player_wallets%rowtype; today date:=current_date; key text:='daily:'||current_date::text;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if (select count(*) from public.experience_transactions where user_id=actor and created_at>=date_trunc('day',now()))<3 then raise exception 'Complete three learning activities first'; end if;
  insert into public.mission_claims(user_id,mission_key,period_start) values(actor,'daily_three_activities',today) on conflict do nothing;
  if not found then raise exception 'Mission already claimed'; end if;
  insert into public.player_wallets(user_id) values(actor) on conflict do nothing;
  select * into wallet from public.player_wallets where user_id=actor for update;
  insert into public.coin_transactions(user_id,idempotency_key,amount,reason) values(actor,key,25,'daily_mission') on conflict do nothing;
  if found then update public.player_wallets set coin_balance=coin_balance+25,updated_at=now() where user_id=actor returning * into wallet; end if;
  return jsonb_build_object('coin_balance',wallet.coin_balance,'reward',25);
end $$;
create or replace function public.get_my_v2_profile()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select jsonb_build_object('profile',to_jsonb(p),'xp_total',coalesce(w.xp_total,0),'coin_balance',coalesce(w.coin_balance,0),
    'settings',to_jsonb(ps),'equipped',coalesce(pa.equipped_items,'{}'::jsonb)) into result
  from public.profiles p left join public.player_wallets w on w.user_id=p.id left join public.player_settings ps on ps.user_id=p.id
  left join public.player_avatar pa on pa.user_id=p.id where p.id=actor;
  return result;
end $$;
create or replace function public.get_leaderboard(p_weekly boolean default false)
returns table(username text,display_name text,avatar_url text,score bigint,position bigint)
language sql stable security definer set search_path = '' as $$
  with scores as (
    select p.username,p.display_name,p.avatar_url,
      case when p_weekly then coalesce(sum(et.amount),0)::bigint else coalesce(w.xp_total,0) end total
    from public.profiles p join public.player_settings ps on ps.user_id=p.id and ps.show_profile and ps.show_xp
    left join public.player_wallets w on w.user_id=p.id
    left join public.experience_transactions et on et.user_id=p.id and p_weekly and et.created_at>=now()-interval '7 days'
    group by p.id,p.username,p.display_name,p.avatar_url,p_weekly,w.xp_total
  ) select s.username,s.display_name,s.avatar_url,s.total,row_number() over(order by s.total desc,s.username)::bigint
  from scores s order by s.total desc,s.username limit 100
$$;

revoke all on function public.is_profile_public(uuid) from public;
revoke all on function public.claim_learning_completion(text,text),public.purchase_avatar_item(text),public.equip_avatar_item(text),public.claim_daily_mission(),public.get_my_v2_profile() from public,anon;
revoke all on function public.get_leaderboard(boolean) from public;
grant execute on function public.is_profile_public(uuid),public.get_leaderboard(boolean) to anon,authenticated;
grant execute on function public.claim_learning_completion(text,text),public.purchase_avatar_item(text),public.equip_avatar_item(text),public.claim_daily_mission(),public.get_my_v2_profile() to authenticated;
insert into public.activity_catalog values
('phrase:HOLA, ¿COMO ESTAS?','phrase','HOLA, ¿COMO ESTAS?',20,4),('phrase:MUCHO GUSTO','phrase','MUCHO GUSTO',20,4),('phrase:BUENOS DIAS','phrase','BUENOS DIAS',20,4),('phrase:BUENAS NOCHES','phrase','BUENAS NOCHES',20,4),('phrase:MI NOMBRE ES...','phrase','MI NOMBRE ES...',20,4),('phrase:¿COMO TE LLAMAS?','phrase','¿COMO TE LLAMAS?',20,4),('phrase:SOY DE MEXICO','phrase','SOY DE MEXICO',20,4),('phrase:MUCHO GUSTO EN CONOCERTE','phrase','MUCHO GUSTO EN CONOCERTE',20,4),('phrase:POR FAVOR','phrase','POR FAVOR',20,4),('phrase:MUCHAS GRACIAS','phrase','MUCHAS GRACIAS',20,4),('phrase:¿PUEDES AYUDARME?','phrase','¿PUEDES AYUDARME?',20,4),('phrase:NO ENTIENDO','phrase','NO ENTIENDO',20,4),('phrase:QUIERO APRENDER','phrase','QUIERO APRENDER',20,4),('phrase:ESTOY ESTUDIANDO','phrase','ESTOY ESTUDIANDO',20,4),('phrase:ME GUSTA APRENDER','phrase','ME GUSTA APRENDER',20,4),('phrase:¿PUEDES REPETIR?','phrase','¿PUEDES REPETIR?',20,4),('phrase:HOLA, MI NOMBRE ES...','phrase','HOLA, MI NOMBRE ES...',20,4),('phrase:ESTOY APRENDIENDO LSM','phrase','ESTOY APRENDIENDO LSM',20,4),('phrase:GRACIAS POR TU AYUDA','phrase','GRACIAS POR TU AYUDA',20,4),('phrase:ME GUSTA COMUNICARME CONTIGO','phrase','ME GUSTA COMUNICARME CONTIGO',20,4)
on conflict(activity_id) do nothing;
