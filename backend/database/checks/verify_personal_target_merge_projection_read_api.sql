\set ON_ERROR_STOP on
DO $check$
DECLARE
  context_function regprocedure := 'app_data.read_personal_merge_projection_context_v1(text,text,uuid)'::regprocedure;
  bridge_function regprocedure := 'app_data.read_personal_known_source_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  core_function regprocedure := 'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  candidate regprocedure;
  body text;
  fragment text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0123_personal_target_merge_projection_read_api') <> 1
  THEN RAISE EXCEPTION '0123 read API migration is missing'; END IF;
  FOREACH candidate IN ARRAY ARRAY[context_function,bridge_function] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_proc core ON core.oid = core_function
        WHERE f.oid = candidate AND f.proowner = core.proowner AND f.prosecdef
          AND f.prorettype = 'jsonb'::regtype AND NOT f.proretset
          AND f.proconfig = ARRAY['search_path=pg_catalog']::text[]
          AND f.provolatile = CASE WHEN candidate = context_function THEN 's'::"char" ELSE 'v'::"char" END
          AND f.proargnames = CASE WHEN candidate = context_function
            THEN ARRAY['trusted_issuer','trusted_subject','trusted_project_id']::text[]
            ELSE ARRAY['trusted_issuer','trusted_subject','trusted_project_id','requested_generation_id']::text[] END)
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR NOT has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) acl
        WHERE f.oid = candidate AND acl.grantee NOT IN (f.proowner,'tongxingzhe_runtime'::regrole::oid))
    THEN RAISE EXCEPTION '0123 read API signature, owner, volatility or ACL drift: %', candidate; END IF;
  END LOOP;
  IF has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
    OR has_function_privilege('tongxingzhe_runtime',core_function,'EXECUTE')
    OR has_function_privilege('public',core_function,'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'app_private' AND c.relkind IN ('r','p')
        AND has_table_privilege('tongxingzhe_runtime',c.oid,'SELECT,INSERT,UPDATE,DELETE'))
    OR has_table_privilege('tongxingzhe_runtime','app_data.external_identities','SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege('tongxingzhe_runtime','app_data.promotion_target_access_events','SELECT,INSERT,UPDATE,DELETE')
    OR has_function_privilege('tongxingzhe_runtime',
      'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION '0123 read API must not open private schema, writers or underlying tables'; END IF;

  SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO body FROM pg_proc WHERE oid = context_function;
  body := regexp_replace(body,'\s+',' ','g');
  IF body ~ '\m(insert|update|delete|perform|execute|call)\M|bootstrap|list_personal_project_contexts|management_analysis_current_contexts|promotion_target_access_events'
  THEN RAISE EXCEPTION '0123 context must read personal eligibility without writes or navigation repair'; END IF;
  FOREACH fragment IN ARRAY ARRAY[
    'char_length(trusted_issuer) > 2048','char_length(trusted_subject) > 512',
    'trusted_issuer is null or btrim(trusted_issuer) = ''''',
    'trusted_subject is null or btrim(trusted_subject) = ''''',
    'trusted_project_id is null','identity_row.issuer = trusted_issuer',
    'identity_row.subject = trusted_subject','actor.status = ''active''',
    'workspace_row.personal_owner_app_user_id = actor.app_user_id',
    'workspace_row.workspace_kind = ''personal''','workspace_row.deleted_at is null',
    'current_project.app_user_id = actor.app_user_id','current_project.project_id = trusted_project_id',
    'project_row.workspace_id = workspace_row.workspace_id','project_row.status = ''active''',
    '''app_user_id''','''workspace_id''','''workspace_kind''','''project_id''','''capabilities''',
    '''view_assigned_target_pii''','''manage_assigned_target_merges''','errcode = ''22023''','errcode = ''42501'''
  ] LOOP
    IF strpos(body,fragment) = 0 THEN RAISE EXCEPTION '0123 context requirement missing: %',fragment; END IF;
  END LOOP;
  SELECT regexp_replace(lower(prosrc),'\s+',' ','g') INTO body FROM pg_proc WHERE oid = bridge_function;
  IF btrim(body) <> 'begin return app_private.read_authorized_known_source_personal_merge_projection_v1( trusted_issuer, trusted_subject, trusted_project_id, requested_generation_id ); end'
  THEN RAISE EXCEPTION '0123 bridge must return exactly one unchanged 0122 core call'; END IF;
END
$check$;
