\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  event_table regclass := 'app_private.personal_target_merge_end_events_v1'::regclass;
  end_function regprocedure :=
    'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure;
  expiry_function regprocedure :=
    'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  definition text;
  fence_position integer;
  target_lock_position integer;
  assignment_lock_position integer;
  delete_position integer;
  event_constraint text;
BEGIN
  SELECT proowner INTO STRICT trusted_owner
  FROM pg_proc WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0120_personal_target_known_source_merge_expiry') <> 1
    OR (SELECT relowner FROM pg_class WHERE oid = event_table) IS DISTINCT FROM trusted_owner
  THEN RAISE EXCEPTION '0120 migration record or event table owner drift'; END IF;

  SELECT lower(pg_get_constraintdef(oid)) INTO event_constraint
  FROM pg_constraint
  WHERE conrelid = event_table AND conname = 'personal_target_merge_end_operation_reason';
  IF event_constraint IS NULL
    OR strpos(event_constraint, 'personal_target_known_source_merge_end') = 0
    OR strpos(event_constraint, 'known_source_split') = 0
    OR strpos(event_constraint, 'personal_target_known_source_merge_expire') = 0
    OR strpos(event_constraint, 'retention_expired') = 0
    OR strpos(event_constraint, ' or ') = 0
  THEN RAISE EXCEPTION '0120 end event operation/reason constraint drift'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = end_function
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = expiry_function
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public', end_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', end_function, 'EXECUTE')
    OR has_function_privilege('public', expiry_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', expiry_function, 'EXECUTE')
    OR (SELECT proargnames FROM pg_proc WHERE oid = expiry_function) IS DISTINCT FROM
      ARRAY['trusted_app_user_id','trusted_workspace_id','trusted_project_id',
        'requested_request_id','requested_generation_id']::text[]
    OR pg_get_function_result(expiry_function) <> 'timestamp with time zone'
  THEN RAISE EXCEPTION '0120 end/expiry function owner, ACL, security, or signature drift'; END IF;

  SELECT pg_get_functiondef(end_function) INTO definition;
  IF strpos(definition,
      'replay_row.operation <> ''personal_target_known_source_merge_end''') = 0
    OR strpos(definition,
      'replay_row.reason <> ''known_source_split''') = 0
  THEN RAISE EXCEPTION '0120 existing end replay does not validate its operation/reason'; END IF;

  SELECT pg_get_functiondef(expiry_function) INTO definition;
  fence_position := strpos(definition,
    'PERFORM app_private.acquire_personal_target_merge_generation_fence_v1()');
  target_lock_position := strpos(definition,
    'ORDER BY candidate.created_at, candidate.promotion_target_id');
  assignment_lock_position := strpos(definition,
    'ORDER BY assignment_row.promotion_target_id');
  delete_position := strpos(definition,
    'DELETE FROM app_private.personal_target_merge_active_members_v1');
  IF strpos(definition, 'pg_advisory_xact_lock') = 0
    OR strpos(definition, 'trusted_app_user_id::text || '':'' || requested_request_id::text') = 0
    OR fence_position = 0 OR target_lock_position = 0 OR assignment_lock_position = 0
    OR delete_position = 0
    OR NOT (fence_position < target_lock_position
      AND target_lock_position < assignment_lock_position
      AND assignment_lock_position < delete_position)
    OR strpos(substring(definition FROM fence_position), 'clock_timestamp()') = 0
    OR strpos(substring(definition FROM fence_position), 'promotion_target_context_authorized') = 0
    OR strpos(substring(definition FROM fence_position), 'personal_target_merge_known_source_manifest_v1') = 0
    OR strpos(definition, 'min(app_data.promotion_target_review_due_at') = 0
    OR strpos(definition, 'pair_due_at > expired_at_value') = 0
    OR strpos(definition, '''personal_target_known_source_merge_expire'', ''retention_expired'', ''ended''') = 0
    OR strpos(definition, 'app_data.anonymize_promotion_target_internal(') = 0
    OR strpos(definition, 'app_data.promotion_target_retention_events') = 0
    OR strpos(definition, 'expired_at_value') = 0
    OR strpos(definition, 'locked_count <> 2') = 0
    OR strpos(definition, 'FOR UPDATE') = 0
    OR strpos(definition,
      'replay_row.operation <> ''personal_target_known_source_merge_expire''') = 0
    OR strpos(definition, 'replay_row.reason <> ''retention_expired''') = 0
    OR strpos(definition, 'RETURN replay_row.ended_at_utc') = 0
  THEN RAISE EXCEPTION '0120 expiry function behavior or lock order drift'; END IF;
END
$check$;
