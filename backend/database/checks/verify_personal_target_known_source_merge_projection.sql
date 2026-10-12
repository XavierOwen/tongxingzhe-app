\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  projection_function regprocedure :=
    'app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  definition text;
  top_level_keys text[] := ARRAY[
    'generation_id','workspace_id','project_id','target_type','retained_target_id',
    'display_name','phone','email','display_name_source_target_id',
    'phone_source_target_id','email_source_target_id','review_due_at_utc','sources'
  ];
  source_keys text[] := ARRAY[
    'target_id','profile','review_due_at_utc','project_relationship',
    'contact_links','institution_relationships'
  ];
  required_refs text[] := ARRAY[
    'app_private.personal_target_merge_generations_v1',
    'app_private.personal_target_merge_generation_members_v1',
    'app_private.personal_target_merge_active_members_v1',
    'app_private.personal_target_merge_activation_requests_v1',
    'app_private.personal_target_merge_end_events_v1',
    'app_data.promotion_targets',
    'app_data.promotion_target_assignments',
    'app_data.promotion_target_review_due_at',
    'app_data.promotion_target_document',
    'app_data.promotion_target_relationship_document',
    'app_data.contacts',
    'app_data.contact_target_links',
    'app_data.promotion_target_institution_relationships',
    'app_data.promotion_target_institution_relation_document'
  ];
  key text;
BEGIN
  SELECT proowner INTO STRICT trusted_owner
  FROM pg_proc WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0121_personal_target_known_source_merge_projection') <> 1
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = projection_function
      AND proowner = trusted_owner AND prosecdef AND provolatile = 's'
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public', projection_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', projection_function, 'EXECUTE')
    OR (SELECT proargnames FROM pg_proc WHERE oid = projection_function) IS DISTINCT FROM
      ARRAY['trusted_app_user_id','trusted_workspace_id','trusted_project_id',
        'requested_generation_id']::text[]
    OR pg_get_function_result(projection_function) <> 'jsonb'
  THEN RAISE EXCEPTION '0121 projection migration or function contract drift'; END IF;

  SELECT lower(pg_get_functiondef(projection_function)) INTO definition;
  IF strpos(definition, 'context as materialized') = 0
    OR strpos(definition, 'generation as materialized') = 0
    OR strpos(definition, 'choices as materialized') = 0
    OR strpos(definition, 'source_targets as materialized') = 0
    OR strpos(definition, 'gate as materialized') = 0
    OR strpos(definition, 'statement_timestamp()') = 0
    OR strpos(definition, 'current_revision') = 0
    OR strpos(definition, 'choice.display_name_source_target_id') = 0
    OR strpos(definition, 'choice.phone_source_target_id') = 0
    OR strpos(definition, 'choice.email_source_target_id') = 0
    OR strpos(definition, 'app_data.promotion_target_document(') = 0
    OR strpos(definition, 'app_data.promotion_target_relationship_document(') = 0
    OR strpos(definition, 'app_data.promotion_target_institution_relation_document(') = 0
    OR strpos(definition, '42501') = 0
    OR strpos(definition, '55000') = 0
    OR strpos(definition, '22023') = 0
    OR strpos(definition, 'for update') > 0
    OR strpos(definition, 'for share') > 0
    OR strpos(definition, 'pg_advisory_xact_lock') > 0
    OR strpos(definition, 'acquire_personal_target_merge_generation_fence') > 0
    OR strpos(definition, 'insert into ') > 0
    OR strpos(definition, 'update app_') > 0
    OR strpos(definition, 'delete from ') > 0
    OR strpos(definition, 'promotion_target_retention_tasks') > 0
    OR strpos(definition, 'personal_target_pii_export') > 0
  THEN RAISE EXCEPTION '0121 projection snapshot, helper, or read-only behavior drift'; END IF;

  FOREACH key IN ARRAY required_refs LOOP
    IF strpos(definition, key) = 0 THEN
      RAISE EXCEPTION '0121 projection source/helper missing: %', key;
    END IF;
  END LOOP;
  FOREACH key IN ARRAY top_level_keys LOOP
    IF strpos(definition, quote_literal(key)) = 0 THEN
      RAISE EXCEPTION '0121 projection top-level JSON key missing: %', key;
    END IF;
  END LOOP;
  FOREACH key IN ARRAY source_keys LOOP
    IF strpos(definition, quote_literal(key)) = 0 THEN
      RAISE EXCEPTION '0121 projection source JSON key missing: %', key;
    END IF;
  END LOOP;
END
$check$;
