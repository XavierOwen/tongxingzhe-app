\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  event_table regclass := 'app_private.personal_target_assignment_end_events_v1'::regclass;
  end_function regprocedure := 'app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  actual_names text[];
  actual_types text[];
  definition text;
  fence_position integer;
  target_lock_position integer;
  assignment_lock_position integer;
BEGIN
  SELECT proowner INTO STRICT trusted_owner
  FROM pg_proc WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0118_personal_target_assignment_end') <> 1
    OR (SELECT relowner FROM pg_class WHERE oid = event_table) IS DISTINCT FROM trusted_owner
    OR has_table_privilege('public',event_table,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime',event_table,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR EXISTS (SELECT 1 FROM pg_class AS c CROSS JOIN LATERAL
      aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) AS a
      WHERE c.oid = event_table AND a.grantee = 0)
  THEN RAISE EXCEPTION '0118 event table owner/ACL or migration record drift'; END IF;

  SELECT array_agg(attname::text ORDER BY attnum),
    array_agg(format_type(atttypid,atttypmod) ORDER BY attnum)
  INTO actual_names,actual_types
  FROM pg_attribute WHERE attrelid = event_table AND attnum > 0 AND NOT attisdropped;
  IF actual_names IS DISTINCT FROM ARRAY[
      'assignment_id','actor_app_user_id','workspace_id','project_id','reason','ended_at_utc'
    ]::text[]
    OR actual_types IS DISTINCT FROM ARRAY[
      'uuid','uuid','uuid','uuid','text','timestamp with time zone'
    ]::text[]
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'p' AND conkey = ARRAY[1]::smallint[])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%user_requested%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%isfinite%')
    OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table AND contype = 'f')
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = event_table
      AND tgtype = 27 AND tgenabled = 'O' AND NOT tgisinternal)
  THEN RAISE EXCEPTION '0118 value-free append-only event shape drift'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = end_function
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public',end_function,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',end_function,'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc AS p CROSS JOIN LATERAL
      aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) AS a
      WHERE p.oid = end_function AND a.grantee = 0)
    OR (SELECT proargnames FROM pg_proc WHERE oid = end_function) IS DISTINCT FROM
      ARRAY['trusted_app_user_id','trusted_workspace_id','trusted_project_id','requested_assignment_id']::text[]
    OR pg_get_function_result(end_function) <> 'timestamp with time zone'
  THEN RAISE EXCEPTION '0118 function owner/security/ACL/signature drift'; END IF;

  SELECT pg_get_functiondef(end_function) INTO definition;
  fence_position := strpos(definition,
    'PERFORM app_private.acquire_personal_target_merge_generation_fence_v1()');
  target_lock_position := strpos(definition,
    'AND candidate.status = ''active''');
  assignment_lock_position := strpos(definition,
    'AND candidate.ended_at IS NULL');
  IF strpos(definition,'''user_requested''') = 0
    OR strpos(definition,'personal_target_merge_active_members_v1') = 0
    OR strpos(definition,'assignment_end_events_v1') = 0
    OR strpos(definition,'promotion_target_retention_events') > 0
    OR fence_position = 0 OR target_lock_position = 0 OR assignment_lock_position = 0
    OR NOT (fence_position < target_lock_position AND target_lock_position < assignment_lock_position)
    OR strpos(substring(definition FROM fence_position),'promotion_target_context_authorized') = 0
    OR strpos(substring(definition FROM fence_position),'current_project.project_id = trusted_project_id') = 0
    OR strpos(definition,'current_project.project_id = trusted_project_id') = 0
  THEN RAISE EXCEPTION '0118 end function behavior or side-effect boundary drift'; END IF;
END
$check$;
