\set ON_ERROR_STOP on
DO $check$
DECLARE
  lower_function regprocedure := 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  core_function regprocedure := 'app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure;
  bridge_function regprocedure := 'app_data.read_personal_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure;
  candidate regprocedure;
  body text;
  code text;
  command_body text;
  fragment text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0125_personal_target_authorized_merge_split_plan') <> 1
  THEN RAISE EXCEPTION '0125 authorized split-plan migration is missing'; END IF;
  FOREACH candidate IN ARRAY ARRAY[core_function,bridge_function] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_proc lower_reader ON lower_reader.oid = lower_function
        WHERE f.oid = candidate AND f.proowner = lower_reader.proowner AND f.prosecdef AND f.provolatile = 'v'
          AND f.prorettype = 'jsonb'::regtype AND NOT f.proretset
          AND f.proargnames = ARRAY['trusted_issuer','trusted_subject','trusted_project_id','requested_generation_id']::text[]
          AND f.proconfig = ARRAY[CASE WHEN candidate = core_function
            THEN 'search_path=pg_catalog, app_data, app_private' ELSE 'search_path=pg_catalog' END]::text[])
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE') IS DISTINCT FROM (candidate = bridge_function)
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) acl
        WHERE f.oid = candidate AND acl.grantee <> f.proowner
          AND NOT (candidate = bridge_function AND acl.grantee = 'tongxingzhe_runtime'::regrole::oid))
    THEN RAISE EXCEPTION '0125 authorized split-plan owner, signature, volatility or ACL drift: %',candidate; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = lower_function AND provolatile = 's' AND prosecdef)
    OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
    OR has_function_privilege('tongxingzhe_runtime',lower_function,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)','EXECUTE')
    OR has_table_privilege('tongxingzhe_runtime','app_data.promotion_target_access_events','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('tongxingzhe_runtime','app_data.external_identities','SELECT,INSERT,UPDATE,DELETE')
  THEN RAISE EXCEPTION '0125 split-plan bridge must not open private readers or base tables'; END IF;

  SELECT regexp_replace(lower(prosrc),'\s+',' ','g') INTO body FROM pg_proc WHERE oid = bridge_function;
  IF btrim(body) <> 'begin return app_private.read_authorized_known_source_merge_split_plan_v1( trusted_issuer, trusted_subject, trusted_project_id, requested_generation_id ); end'
  THEN RAISE EXCEPTION '0125 runtime bridge must return exactly one unchanged private core call'; END IF;
  SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO body FROM pg_proc WHERE oid = core_function;
  body := regexp_replace(body,'\s+',' ','g');
  code := regexp_replace(body,'''(''''|[^''])*''','''''','g');
  command_body := substring(code FROM 'with context as materialized \(.*?;');
  IF command_body IS NULL OR replace(code,command_body,'') ~ '\m(select|with|insert)\M'
    OR code ~ '\m(update|delete|perform|execute|call|truncate|create|alter|drop|grant)\M|for (update|share)|pg_advisory|bootstrap|fence|expiry'
    OR (SELECT count(*) FROM regexp_matches(code,'\minsert\M','g')) <> 1
    OR (SELECT count(*) FROM regexp_matches(code,'app_data\.read_personal_merge_projection_context_v1\s*\(','g')) <> 1
    OR (SELECT count(*) FROM regexp_matches(code,'app_private\.read_known_source_personal_merge_split_plan_v1\s*\(','g')) <> 1
    OR regexp_replace(regexp_replace(regexp_replace(code,
      'app_data\.read_personal_merge_projection_context_v1\s*\(','','g'),
      'app_private\.read_known_source_personal_merge_split_plan_v1\s*\(','','g'),
      'insert into app_data\.promotion_target_access_events\s*\(','','g') ~ 'app_(data|private)\.[a-z0-9_]+\s*\('
  THEN RAISE EXCEPTION '0125 must share one context/plan/audit command and write only member views'; END IF;
  FOREACH fragment IN ARRAY ARRAY[
    'requested_generation_id is null','errcode = ''22023''',
    'trusted_issuer, trusted_subject, trusted_project_id',
    'planned as materialized','(context.document ->> ''app_user_id'')::uuid',
    '(context.document ->> ''workspace_id'')::uuid','trusted_project_id, requested_generation_id',
    'insert into app_data.promotion_target_access_events',
    'jsonb_array_elements_text(planned.document -> ''member_target_ids'')',
    'member.target_id::uuid','planned.app_user_id, ''viewed'', statement_timestamp()',
    'select planned.document, access_count.inserted_count','into split_plan, inserted_count',
    'select count(*) as inserted_count from inserted_access_events',
    'if inserted_count <> 2 then','errcode = ''55000''','return split_plan;'
  ] LOOP
    IF strpos(body,fragment) = 0 THEN RAISE EXCEPTION '0125 authorization/audit contract missing: %',fragment; END IF;
  END LOOP;
END
$check$;
