-- Run only after migrations 001–010 have completed successfully in an empty project.
-- Executes read-only catalog assertions. Any failed security invariant raises an error.
do $$
begin
 if not (select relrowsecurity from pg_class where oid='public.profiles'::regclass) then raise exception 'FAIL: profiles RLS disabled'; end if;
 if not (select relrowsecurity from pg_class where oid='public.player_progress'::regclass) then raise exception 'FAIL: player_progress RLS disabled'; end if;
 if not (select relrowsecurity from pg_class where oid='public.player_wallets'::regclass) then raise exception 'FAIL: player_wallets RLS disabled'; end if;
 if not (select relrowsecurity from pg_class where oid='public.coin_transactions'::regclass) then raise exception 'FAIL: coin ledger RLS disabled'; end if;
 if not (select relrowsecurity from pg_class where oid='public.player_assessment_sessions'::regclass) then raise exception 'FAIL: assessment sessions RLS disabled'; end if;
 if has_table_privilege('anon','public.profiles','SELECT') or has_table_privilege('authenticated','public.profiles','SELECT') then raise exception 'FAIL: direct profile reads granted'; end if;
 if has_table_privilege('authenticated','public.player_wallets','UPDATE') or has_table_privilege('authenticated','public.coin_transactions','INSERT') then raise exception 'FAIL: client wallet/ledger writes granted'; end if;
 if has_table_privilege('authenticated','public.player_assessment_sessions','SELECT') or has_table_privilege('authenticated','public.player_assessment_scores','INSERT') then raise exception 'FAIL: client assessment access too broad'; end if;
 if has_function_privilege('anon','public.get_my_v2_profile()','EXECUTE') then raise exception 'FAIL: anon can call private profile RPC'; end if;
 if has_function_privilege('anon','public.is_profile_public(uuid)','EXECUTE') then raise exception 'FAIL: anon can query profile visibility by UUID'; end if;
 if not has_function_privilege('anon','public.get_public_profile(text)','EXECUTE') then raise exception 'FAIL: public profile projection unavailable'; end if;
 if has_function_privilege('authenticated','public.record_challenge_activity(text,text)','EXECUTE') then raise exception 'FAIL: clients can forge challenge activity'; end if;
 if has_function_privilege('authenticated','public.claim_learning_completion(text,text)','EXECUTE') or has_function_privilege('authenticated','public.claim_daily_mission()','EXECUTE') or has_function_privilege('authenticated','public.purchase_avatar_item(text)','EXECUTE') then raise exception 'FAIL: economic RPCs remain enabled'; end if;
 if position('server validation' in lower(pg_get_functiondef('public.record_stage_completion(uuid)'::regprocedure)))=0 then raise exception 'FAIL: unverified stage completion is not disabled'; end if;
 if position('asset_token' in pg_get_functiondef('public.start_learning_assessment()'::regprocedure))=0 then raise exception 'FAIL: assessment opaque asset mapping missing'; end if;
 if position('public_q' in pg_get_functiondef('public.start_learning_assessment()'::regprocedure))=0 then raise exception 'FAIL: assessment public projection missing'; end if;
 raise notice 'PASS: 16 catalog, RLS, and privilege checks';
end $$;

