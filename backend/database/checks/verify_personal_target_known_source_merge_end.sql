\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  event_table regclass := 'app_private.personal_target_merge_end_events_v1'::regclass;
  active_table regclass := 'app_private.personal_target_merge_active_members_v1'::regclass;
  manifest_function regprocedure :=
    'app_private.personal_target_merge_known_source_manifest_v1(uuid)'::regprocedure;
  end_function regprocedure :=
    'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure;
  trigger_function regprocedure :=
    'app_private.reject_ended_personal_target_merge_activation_v1()'::regprocedure;
  manifest_definition text;
  guard_definition text;
  actual_names text[];
  actual_types text[];
  definition text;
  expected_indexes text[] := ARRAY[
    'contact_target_links_merge_generation',
    'pt_relationships_merge_generation',
    'pt_relationship_revisions_merge_generation',
    'pt_institution_relationships_person_generation',
    'pt_institution_relationships_institution_generation',
    'pt_institution_revisions_person_generation',
    'pt_institution_revisions_institution_generation'
  ];
  fence_position integer;
  target_lock_position integer;
  assignment_lock_position integer;
  guard_fence_position integer;
  guard_event_position integer;
BEGIN
  SELECT proowner INTO STRICT trusted_owner
  FROM pg_proc WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0119_personal_target_known_source_merge_end') <> 1
    OR (SELECT relowner FROM pg_class WHERE oid = event_table) IS DISTINCT FROM trusted_owner
    OR has_table_privilege('public',event_table,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime',event_table,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR EXISTS (SELECT 1 FROM pg_class AS c CROSS JOIN LATERAL
      aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) AS a
      WHERE c.oid = event_table AND a.grantee = 0)
  THEN RAISE EXCEPTION '0119 event table owner/ACL or migration record drift'; END IF;

  SELECT array_agg(attname::text ORDER BY attnum),
    array_agg(format_type(atttypid,atttypmod) ORDER BY attnum)
  INTO actual_names,actual_types
  FROM pg_attribute WHERE attrelid = event_table AND attnum > 0 AND NOT attisdropped;
  IF actual_names IS DISTINCT FROM ARRAY[
      'generation_id','actor_app_user_id','workspace_id','project_id','request_id',
      'operation','reason','outcome','fact_fingerprint','fact_count','target_count','ended_at_utc'
    ]::text[]
    OR actual_types IS DISTINCT FROM ARRAY[
      'uuid','uuid','uuid','uuid','uuid','text','text','text','text','bigint','integer',
      'timestamp with time zone'
    ]::text[]
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'p' AND conkey = ARRAY[1]::smallint[])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'f' AND conkey = ARRAY[1]::smallint[])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'f' AND conkey = ARRAY[1]::smallint[]
      AND confrelid = 'app_private.personal_target_merge_generations_v1'::regclass)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'u' AND conkey = ARRAY[2,5]::smallint[])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND lower(pg_get_constraintdef(oid)) LIKE '%personal_target_known_source_merge_end%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND lower(pg_get_constraintdef(oid)) LIKE '%known_source_split%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND lower(pg_get_constraintdef(oid)) LIKE '%ended%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND lower(pg_get_constraintdef(oid)) LIKE '%fact_count% >= 0%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND lower(pg_get_constraintdef(oid)) LIKE '%target_count% = 2%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%^[0-9a-f]{64}$%')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = event_table
      AND contype = 'c' AND lower(pg_get_constraintdef(oid)) LIKE '%isfinite%')
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = event_table
      AND tgfoid = 'app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure
      AND tgtype = 27 AND tgenabled = 'O' AND NOT tgisinternal)
  THEN RAISE EXCEPTION '0119 value-free append-only event shape drift'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = manifest_function
      AND proowner = trusted_owner AND prosecdef AND provolatile = 's'
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public',manifest_function,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',manifest_function,'EXECUTE')
    OR (SELECT proargnames FROM pg_proc WHERE oid = manifest_function) IS DISTINCT FROM
      ARRAY['requested_generation_id','fact_count','fact_fingerprint']::text[]
    OR pg_get_function_result(manifest_function) <> 'TABLE(fact_count bigint, fact_fingerprint text)'
  THEN RAISE EXCEPTION '0119 manifest helper owner/security/ACL/signature drift'; END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(expected_indexes) AS expected(index_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_class AS index_row
      JOIN pg_index AS index_meta ON index_meta.indexrelid = index_row.oid
      WHERE index_row.relname = expected.index_name
        AND index_meta.indisvalid AND index_meta.indisready
        AND index_meta.indnkeyatts = 1
        AND pg_get_expr(index_meta.indpred,index_meta.indrelid) LIKE '%IS NOT NULL%'
    )
  ) OR (SELECT count(*) FROM pg_class AS index_row
      JOIN pg_index AS index_meta ON index_meta.indexrelid = index_row.oid
      WHERE index_row.relname = ANY(expected_indexes)) <> cardinality(expected_indexes)
  THEN RAISE EXCEPTION '0119 source manifest indexes drift'; END IF;

  SELECT pg_get_functiondef(manifest_function) INTO manifest_definition;
  IF to_regprocedure('app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)') IS NOT NULL THEN
    IF strpos(manifest_definition,'personal_target_merge_known_source_fact_catalog_v1(') = 0 THEN
      RAISE EXCEPTION '0119 manifest must use the shared fact catalog when present';
    END IF;
    manifest_definition := manifest_definition || pg_get_functiondef(
      'app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)'::regprocedure
    );
  END IF;
  IF strpos(manifest_definition,'app_data.contact_target_links') = 0
    OR strpos(manifest_definition,'app_data.promotion_target_project_relationships') = 0
    OR strpos(manifest_definition,'app_data.promotion_target_relationship_revisions') = 0
    OR strpos(manifest_definition,'app_data.promotion_target_institution_relationships') = 0
    OR strpos(manifest_definition,'app_data.promotion_target_institution_relation_revisions') = 0
    OR strpos(manifest_definition,'updated_at') = 0
    OR strpos(manifest_definition,'current_revision') = 0
    OR strpos(manifest_definition,'app_data.contacts') > 0
    OR strpos(manifest_definition,'display_name') > 0
    OR strpos(manifest_definition,'phone') > 0
    OR strpos(manifest_definition,'email') > 0
    OR strpos(manifest_definition,'follow_up_note') > 0
    OR strpos(manifest_definition,'reason_detail') > 0
    OR strpos(manifest_definition,'occurred_at') > 0
  THEN RAISE EXCEPTION '0119 manifest sources or metadata boundary drift'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = end_function
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public',end_function,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',end_function,'EXECUTE')
    OR (SELECT proargnames FROM pg_proc WHERE oid = end_function) IS DISTINCT FROM
      ARRAY['trusted_app_user_id','trusted_workspace_id','trusted_project_id','requested_request_id',
        'requested_generation_id','requested_fact_fingerprint']::text[]
    OR pg_get_function_result(end_function) <> 'timestamp with time zone'
    OR (SELECT relowner FROM pg_class WHERE oid = active_table) IS DISTINCT FROM trusted_owner
    OR (SELECT proowner FROM pg_proc WHERE oid = trigger_function) IS DISTINCT FROM trusted_owner
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = trigger_function)
    OR (SELECT proconfig FROM pg_proc WHERE oid = trigger_function) IS DISTINCT FROM
      ARRAY['search_path=pg_catalog, app_private']::text[]
    OR has_function_privilege('public',trigger_function,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',trigger_function,'EXECUTE')
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = active_table
      AND tgfoid = trigger_function AND tgtype = 23 AND tgenabled = 'O' AND NOT tgisinternal)
  THEN RAISE EXCEPTION '0119 end/activation guard owner/security/ACL/signature drift'; END IF;

  SELECT pg_get_functiondef(trigger_function) INTO guard_definition;
  guard_fence_position := strpos(guard_definition,
    'PERFORM app_private.acquire_personal_target_merge_generation_fence_v1()');
  guard_event_position := strpos(guard_definition,
    'FROM app_private.personal_target_merge_end_events_v1 AS event_row');
  IF guard_fence_position = 0 OR guard_event_position = 0
    OR guard_fence_position >= guard_event_position
  THEN RAISE EXCEPTION '0119 activation guard must acquire the generation fence before checking end events'; END IF;

  SELECT pg_get_functiondef(end_function) INTO definition;
  fence_position := strpos(definition,
    'PERFORM app_private.acquire_personal_target_merge_generation_fence_v1()');
  target_lock_position := strpos(definition,
    'ORDER BY candidate.created_at, candidate.promotion_target_id');
  assignment_lock_position := strpos(definition,
    'ORDER BY assignment_row.promotion_target_id');
  IF strpos(definition,'pg_advisory_xact_lock') = 0
    OR strpos(definition,'personal_target_merge_end_events_v1') = 0
    OR strpos(definition,'personal_target_merge_active_members_v1') = 0
    OR strpos(definition,'promotion_target_retention_events') > 0
    OR fence_position = 0 OR target_lock_position = 0 OR assignment_lock_position = 0
    OR NOT (fence_position < target_lock_position AND target_lock_position < assignment_lock_position)
    OR strpos(substring(definition FROM fence_position),'clock_timestamp()') = 0
    OR strpos(substring(definition FROM fence_position),'personal_target_merge_known_source_manifest_v1') = 0
    OR strpos(substring(definition FROM fence_position),'promotion_target_context_authorized') = 0
    OR strpos(definition,'fact_fingerprint') = 0
    OR strpos(definition,'DELETE FROM app_private.personal_target_merge_active_members_v1') = 0
    OR strpos(substring(definition FROM target_lock_position),'FOR UPDATE') = 0
    OR strpos(substring(definition FROM assignment_lock_position),'FOR UPDATE') = 0
    OR strpos(definition,'GET DIAGNOSTICS locked_count = ROW_COUNT') = 0
    OR strpos(definition,'locked_count <> 2') = 0
    OR strpos(definition,'candidate.status = ''active''') = 0
    OR strpos(definition,'promotion_target_review_due_at') = 0
  THEN RAISE EXCEPTION '0119 end function behavior or lock order drift'; END IF;
END
$check$;
