\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  runtime_role oid;
  request_table regclass :=
    'app_private.personal_target_merge_activation_requests_v1'::regclass;
  audit_table regclass :=
    'app_private.personal_target_merge_activation_audit_v1'::regclass;
  activate_function regprocedure :=
    'app_private.activate_personal_target_merge_generation_v2(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  function_definition text;
  authorization_position integer;
  request_lock_position integer;
  replay_position integer;
  fence_position integer;
  receipt_lock_position integer;
  clock_position integer;
  validator_position integer;
  actual_names text[];
  actual_types text[];
  trigger_count integer;
BEGIN
  SELECT procedure_row.proowner INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT role_row.oid INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid = request_table
      AND relation_row.relowner = trusted_owner
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid = audit_table
      AND relation_row.relowner = trusted_owner
  ) OR has_table_privilege(
    'public', request_table,
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR has_table_privilege(
    runtime_role, request_table,
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR has_table_privilege(
    'public', audit_table,
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR has_table_privilege(
    runtime_role, audit_table,
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) THEN
    RAISE EXCEPTION 'activation request/audit table ACL or owner drifted';
  END IF;

  SELECT
    array_agg(attribute_row.attname ORDER BY attribute_row.attnum),
    array_agg(pg_catalog.format_type(attribute_row.atttypid, NULL)
      ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = request_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;
  IF actual_names IS DISTINCT FROM ARRAY[
      'actor_app_user_id', 'request_id', 'workspace_id', 'preview_id',
      'retained_target_id', 'display_name_source_target_id',
      'phone_source_target_id', 'email_source_target_id', 'generation_id',
      'activated_at_utc'
    ]::text[] OR actual_types IS DISTINCT FROM ARRAY[
      'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid',
      'timestamp with time zone'
    ]::text[] THEN
    RAISE EXCEPTION 'activation request columns drifted';
  END IF;

  SELECT
    array_agg(attribute_row.attname ORDER BY attribute_row.attnum),
    array_agg(pg_catalog.format_type(attribute_row.atttypid, NULL)
      ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = audit_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;
  IF actual_names IS DISTINCT FROM ARRAY[
      'audit_event_id', 'actor_app_user_id', 'workspace_id', 'request_id',
      'operation', 'outcome', 'target_count', 'occurred_at_utc'
    ]::text[] OR actual_types IS DISTINCT FROM ARRAY[
      'uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'integer',
      'timestamp with time zone'
    ]::text[] THEN
    RAISE EXCEPTION 'activation audit columns drifted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = request_table
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid =
        'app_private.personal_target_pair_preview_receipts'::regclass
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = request_table
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid =
        'app_private.personal_target_merge_generations_v1'::regclass
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid IN (request_table, audit_table)
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'display_name', 'phone', 'email', 'name', 'phone_number',
        'email_address', 'payload', 'snapshot', 'raw_value', 'content_hash',
        'field_hash', 'request_hash'
      )
  ) THEN
    RAISE EXCEPTION 'activation history receipt FK or PII boundary drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = request_table
      AND constraint_row.contype = 'p'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%PRIMARY KEY (actor_app_user_id, request_id)%'
  ) OR (
    SELECT count(*) FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = request_table
      AND constraint_row.contype = 'u'
  ) <> 2 OR (
    SELECT count(*) FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'u'
  ) <> 1 THEN
    RAISE EXCEPTION 'activation request/audit uniqueness constraints drifted';
  END IF;

  SELECT count(*) INTO trigger_count
  FROM pg_catalog.pg_trigger AS trigger_row
  WHERE NOT trigger_row.tgisinternal AND (
    (trigger_row.tgrelid = request_table
      AND trigger_row.tgname =
        'personal_target_merge_activation_requests_immutable')
    OR (trigger_row.tgrelid = audit_table
      AND trigger_row.tgname =
        'personal_target_merge_activation_audit_immutable')
  );
  IF trigger_count <> 2 THEN
    RAISE EXCEPTION 'activation request/audit append-only triggers missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS function_row
    WHERE function_row.oid = activate_function
      AND function_row.proowner = trusted_owner
      AND function_row.prosecdef
      AND function_row.provolatile = 'v'
      AND function_row.proconfig @>
        ARRAY['search_path=pg_catalog, app_data, app_private']
  ) OR has_function_privilege('public', activate_function, 'EXECUTE')
    OR has_function_privilege(runtime_role, activate_function, 'EXECUTE')
    OR has_function_privilege(
      'public',
      'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)',
      'EXECUTE'
    ) OR has_function_privilege(
      runtime_role,
      'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)',
      'EXECUTE'
    ) THEN
    RAISE EXCEPTION 'merge activation function ACL or security drifted';
  END IF;

  function_definition := pg_catalog.pg_get_functiondef(activate_function);
  authorization_position := strpos(function_definition,
    'personal target merge generation activation is forbidden');
  request_lock_position := strpos(function_definition, 'pg_advisory_xact_lock');
  replay_position := strpos(function_definition,
    'FROM app_private.personal_target_merge_activation_requests_v1 AS request_row');
  fence_position := strpos(function_definition,
    'acquire_personal_target_merge_generation_fence_v1');
  receipt_lock_position := strpos(function_definition,
    'FOR UPDATE');
  clock_position := strpos(function_definition, 'clock_timestamp()');
  validator_position := strpos(function_definition,
    'validate_personal_target_pair_preview_v1');
  IF authorization_position = 0 OR request_lock_position = 0
    OR replay_position = 0 OR fence_position = 0
    OR receipt_lock_position = 0 OR clock_position = 0
    OR validator_position = 0
    OR NOT (authorization_position < request_lock_position
      AND request_lock_position < replay_position
      AND replay_position < fence_position
      AND fence_position < receipt_lock_position
      AND receipt_lock_position < clock_position
      AND clock_position < validator_position)
  THEN
    RAISE EXCEPTION 'activation authorization/replay/fence/receipt order drifted';
  END IF;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0117_personal_target_merge_receipt_consumption') <> 1
  THEN
    RAISE EXCEPTION '0117 migration was not recorded once';
  END IF;
END
$check$;

SELECT 'personal target merge receipt consumption: passed' AS result;
