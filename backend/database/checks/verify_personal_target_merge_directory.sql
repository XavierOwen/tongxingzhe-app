\set ON_ERROR_STOP on
DO $check$
DECLARE
  core_function regprocedure := 'app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid)'::regprocedure;
  bridge_function regprocedure := 'app_data.read_personal_merge_directory_v1(text,text,uuid,uuid)'::regprocedure;
  owner_function regprocedure := 'app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure;
  candidate regprocedure;
  body text;
  code text;
  command_body text;
  fragment text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version = '0126_personal_target_merge_directory') <> 1
  THEN RAISE EXCEPTION '0126 personal merge directory migration is missing'; END IF;
  FOREACH candidate IN ARRAY ARRAY[core_function,bridge_function] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_proc owner_reader ON owner_reader.oid = owner_function
        WHERE f.oid = candidate AND f.proowner = owner_reader.proowner AND f.prosecdef AND f.provolatile = 'v'
          AND f.prorettype = 'jsonb'::regtype AND NOT f.proretset
          AND f.proargnames = ARRAY['trusted_issuer','trusted_subject','trusted_project_id','requested_after_generation_id']::text[]
          AND f.proconfig = ARRAY[CASE WHEN candidate = core_function
            THEN 'search_path=pg_catalog, app_data, app_private' ELSE 'search_path=pg_catalog' END]::text[])
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE') IS DISTINCT FROM (candidate = bridge_function)
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) acl
        WHERE f.oid = candidate AND acl.grantee <> f.proowner
          AND NOT (candidate = bridge_function AND acl.grantee = 'tongxingzhe_runtime'::regrole::oid))
    THEN RAISE EXCEPTION '0126 directory signature, volatility, owner or ACL drift: %',candidate; END IF;
  END LOOP;
  IF has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
    OR has_function_privilege('tongxingzhe_runtime',owner_function,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_table_privilege('tongxingzhe_runtime','app_data.promotion_target_access_events','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('tongxingzhe_runtime','app_private.personal_target_merge_generations_v1','SELECT,INSERT,UPDATE,DELETE')
  THEN RAISE EXCEPTION '0126 directory must not grant private readers, tables or writers'; END IF;
  SELECT regexp_replace(lower(prosrc),'\s+',' ','g') INTO body FROM pg_proc WHERE oid = bridge_function;
  IF btrim(body) <> 'begin return app_private.read_authorized_personal_merge_directory_v1( trusted_issuer, trusted_subject, trusted_project_id, requested_after_generation_id ); end'
  THEN RAISE EXCEPTION '0126 runtime bridge must return exactly one unchanged private core call'; END IF;
  SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO body FROM pg_proc WHERE oid = core_function;
  body := regexp_replace(body,'\s+',' ','g');
  code := regexp_replace(body,'''(''''|[^''])*''','''''','g');
  command_body := substring(code FROM 'with context as materialized \(.*?;');
  IF command_body IS NULL OR replace(code,command_body,'') ~ '\m(select|with|insert)\M'
    OR code ~ '\m(update|delete|perform|execute|call|truncate|create|alter|drop|grant)\M|for (update|share)|pg_advisory|bootstrap|fence|expiry'
    OR (SELECT count(*) FROM regexp_matches(code,'\minsert\M','g')) <> 1
    OR (SELECT count(*) FROM regexp_matches(code,'app_data\.read_personal_merge_projection_context_v1\s*\(','g')) <> 1
    OR body ~ 'target\.display_name|target\.phone|target\.email|follow_up_note|current_stage|response_level|follow_up_consent|promotion_target_document|read_known_source_personal_target_merge_projection_v1'
  THEN RAISE EXCEPTION '0126 directory must share one authorization/page/audit command without profile values'; END IF;
  FOREACH fragment IN ARRAY ARRAY[
    'eligible as materialized','page as materialized','limit 21','limit 20',
    'requested_after_generation_id is null or generation.generation_id > requested_after_generation_id',
    'members.member_count = 2 and members.context_matches',
    'active_members.member_count = 2 and active_members.context_matches',
    'active_members.target_ids = members.target_ids','sources.member_count = 2 and sources.not_due',
    'retention.review_due_at > statement_timestamp()',
    'choice.actor_app_user_id = (context.document ->> ''app_user_id'')::uuid',
    'choice.workspace_id = generation.workspace_id','choice.retained_target_id = any(members.target_ids)',
    'choice.display_name_source_target_id = any(members.target_ids)',
    'choice.phone_source_target_id = any(members.target_ids)','choice.email_source_target_id = any(members.target_ids)',
    'activation.generation_id = generation.generation_id) = 1',
    'app_private.personal_target_merge_end_events_v1','assignment.ended_at is null',
    'target.status = ''active''','insert into app_data.promotion_target_access_events',
    'from context cross join page','unnest(page.target_ids)',
    '''viewed'', statement_timestamp()','order by page.generation_id',
    '''workspace_id''','''project_id''','''items''','''next_cursor''',
    '''generation_id''','''target_type''','''retained_target_id''','''member_target_ids''','''review_due_at_utc''',
    'case when (select count(*) from eligible) > 20',
    'then (select generation_id from page order by generation_id desc limit 1) end',
    '(select 2 * count(*) from page)','inserted_count is distinct from expected_count',
    'select count(*) as inserted_count from inserted_access_events','errcode = ''55000''','return directory;'
  ] LOOP
    IF strpos(body,fragment) = 0 THEN RAISE EXCEPTION '0126 directory eligibility/page/audit requirement missing: %',fragment; END IF;
  END LOOP;
END
$check$;
