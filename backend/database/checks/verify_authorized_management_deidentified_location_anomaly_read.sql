\set ON_ERROR_STOP on

-- Structural and least-privilege contract for Slice 6CC.  The rollback
-- fixture owns row-level behaviour; this check must pass on an empty database
-- and after pg_dump/pg_restore, without relying on synthetic anomaly rows.
DO $check$
DECLARE
  anomaly_ids_table_oid oid;
  access_events_table_oid oid;
  provenance_table_oid oid;
  contacts_table_oid oid;
  revisions_table_oid oid;
  capability_table_oid oid;
  directory_function regprocedure := to_regprocedure(
    'app_private.list_authorized_deidentified_location_anomalies_v1(uuid,uuid)'
  );
  detail_function regprocedure := to_regprocedure(
    'app_private.read_authorized_deidentified_location_anomaly_v1(uuid,uuid,uuid)'
  );
  resolver_function regprocedure := to_regprocedure(
    'app_private.resolve_management_report_authorization_v1(uuid,uuid,text)'
  );
  capture_function regprocedure := to_regprocedure(
    'app_private.capture_deidentified_location_anomaly_id_v1()'
  );
  validation_function regprocedure := to_regprocedure(
    'app_private.validate_deidentified_location_anomaly_access_v1()'
  );
  table_owner text;
  audit_owner text;
  function_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  function_source text;
  resolver_source text;
  capability_values text[];
  role_name text;
  required_column record;
BEGIN
  anomaly_ids_table_oid = to_regclass(
    'app_private.deidentified_location_anomaly_ids'
  );
  access_events_table_oid = to_regclass(
    'app_private.deidentified_location_anomaly_access_events'
  );
  provenance_table_oid = to_regclass('app_data.contact_location_provenance');
  contacts_table_oid = to_regclass('app_data.contacts');
  revisions_table_oid = to_regclass('app_data.contact_revisions');
  capability_table_oid = to_regclass(
    'app_data.management_report_capability_grants'
  );

  IF anomaly_ids_table_oid IS NULL
    OR access_events_table_oid IS NULL
    OR provenance_table_oid IS NULL
    OR contacts_table_oid IS NULL
    OR revisions_table_oid IS NULL
    OR capability_table_oid IS NULL
    OR directory_function IS NULL
    OR detail_function IS NULL
    OR resolver_function IS NULL
    OR capture_function IS NULL
    OR validation_function IS NULL
  THEN
    RAISE EXCEPTION 'deidentified location anomaly read contract is incomplete';
  END IF;

  -- The new capability is an independent allowlist member.  Extracting the
  -- literals from the actual CHECK expression catches both accidental
  -- omission and silent broadening of the capability surface.
  SELECT array_agg(match[1] ORDER BY match[1])
  INTO capability_values
  FROM pg_catalog.pg_constraint AS constraint_row
  CROSS JOIN LATERAL regexp_matches(
    pg_catalog.pg_get_constraintdef(constraint_row.oid),
    $$'([^']+)'$$,
    'g'
  ) AS match
  WHERE constraint_row.conrelid = capability_table_oid
    AND constraint_row.conname =
      'management_report_capability_grants_capability_id_check'
    AND constraint_row.contype = 'c';

  IF capability_values IS DISTINCT FROM ARRAY[
    'export_management_reports',
    'release_management_reports',
    'view_anonymous_analytics',
    'view_deidentified_anomalies'
  ]::text[] THEN
    RAISE EXCEPTION
      'management capability allowlist is not the fixed 6CC contract: %',
      capability_values;
  END IF;

  SELECT pg_catalog.pg_get_functiondef(resolver_function)
  INTO STRICT resolver_source;

  IF resolver_source !~ $$requested_capability_id[[:space:]]+NOT[[:space:]]+IN$$
    OR resolver_source !~ $$view_anonymous_analytics$$
    OR resolver_source !~ $$release_management_reports$$
    OR resolver_source !~ $$export_management_reports$$
    OR resolver_source !~ $$view_deidentified_anomalies$$
    OR (
      length(resolver_source)
      - length(replace(resolver_source, 'view_deidentified_anomalies', ''))
    ) / length('view_deidentified_anomalies') <> 1
  THEN
    RAISE EXCEPTION
      'management authorization resolver does not pin the 6CC capability allowlist';
  END IF;

  -- Both private relations are owned by the same closed role as all private
  -- anomaly functions.  No existing runtime/report/writer role may own them.
  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT table_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = anomaly_ids_table_oid;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT audit_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = access_events_table_oid;

  IF table_owner IS DISTINCT FROM
      'tongxingzhe_management_deidentified_anomaly_reader'
    OR audit_owner IS DISTINCT FROM table_owner
  THEN
    RAISE EXCEPTION
      'deidentified anomaly private relations have an unsafe owner: % / %',
      table_owner,
      audit_owner;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = table_owner
      AND NOT role_row.rolcanlogin
      AND NOT role_row.rolsuper
      AND NOT role_row.rolcreatedb
      AND NOT role_row.rolcreaterole
      AND NOT role_row.rolinherit
      AND NOT role_row.rolreplication
      AND NOT role_row.rolbypassrls
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS role_row
      ON role_row.oid = membership.roleid
    WHERE role_row.rolname = table_owner
  ) THEN
    RAISE EXCEPTION
      'deidentified anomaly owner must remain a closed NOLOGIN role: %',
      table_owner;
  END IF;

  -- Pin the relation shapes.  In particular, neither the opaque map nor the
  -- audit may grow a value-bearing or identity-bearing column unnoticed.
  IF (
    SELECT array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum)
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = anomaly_ids_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
  ) IS DISTINCT FROM ARRAY[
    'anomaly_id',
    'source_id',
    'mapped_at_utc'
  ]::text[] THEN
    RAISE EXCEPTION 'deidentified anomaly opaque-map columns are not exact';
  END IF;

  IF (
    SELECT array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum)
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = access_events_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
  ) IS DISTINCT FROM ARRAY[
    'access_event_id',
    'requested_by_app_user_id',
    'organization_workspace_id',
    'organization_membership_id',
    'project_membership_id',
    'capability_grant_id',
    'capability_id',
    'authorization_reference_at_utc',
    'project_id',
    'access_kind',
    'result_status',
    'returned_anomaly_count',
    'accessed_at_utc'
  ]::text[] THEN
    RAISE EXCEPTION 'deidentified anomaly audit columns are not value-free';
  END IF;

  FOR required_column IN
    SELECT *
    FROM (
      VALUES
        ('anomaly_id'::text, 'uuid'::text, true),
        ('source_id'::text, 'uuid'::text, true),
        ('mapped_at_utc'::text, 'timestamp with time zone'::text, true)
    ) AS expected(column_name, column_type, required_not_null)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = anomaly_ids_table_oid
        AND attribute_row.attname = required_column.column_name
        AND attribute_row.atttypid::regtype::text = required_column.column_type
        AND attribute_row.attnotnull = required_column.required_not_null
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
    ) THEN
      RAISE EXCEPTION 'deidentified anomaly map column is incomplete: %',
        required_column.column_name;
    END IF;
  END LOOP;

  FOR required_column IN
    SELECT *
    FROM (
      VALUES
        ('access_event_id'::text, 'uuid'::text, true),
        ('requested_by_app_user_id'::text, 'uuid'::text, true),
        ('organization_workspace_id'::text, 'uuid'::text, true),
        ('organization_membership_id'::text, 'uuid'::text, true),
        ('project_membership_id'::text, 'uuid'::text, true),
        ('capability_grant_id'::text, 'uuid'::text, true),
        ('capability_id'::text, 'text'::text, true),
        ('authorization_reference_at_utc'::text,
          'timestamp with time zone'::text, true),
        ('project_id'::text, 'uuid'::text, true),
        ('access_kind'::text, 'text'::text, true),
        ('result_status'::text, 'text'::text, true),
        ('returned_anomaly_count'::text, 'integer'::text, false),
        ('accessed_at_utc'::text, 'timestamp with time zone'::text, true)
    ) AS expected(column_name, column_type, required_not_null)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = access_events_table_oid
        AND attribute_row.attname = required_column.column_name
        AND attribute_row.atttypid::regtype::text = required_column.column_type
        AND attribute_row.attnotnull = required_column.required_not_null
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
    ) THEN
      RAISE EXCEPTION 'deidentified anomaly audit column is incomplete: %',
        required_column.column_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid IN (
      anomaly_ids_table_oid,
      access_events_table_oid
    )
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'contact_id', 'revision_number', 'source_id', 'promoter_id',
        'target_id', 'app_user_id', 'external_subject', 'name', 'address',
        'email', 'phone', 'notes', 'raw_answer', 'answer', 'latitude',
        'longitude', 'accuracy_meters', 'place_name', 'region_id',
        'protected_report', 'cells', 'coordinates', 'pii'
      )
      AND NOT (
        attribute_row.attrelid = anomaly_ids_table_oid
        AND attribute_row.attname = 'source_id'
      )
  ) THEN
    RAISE EXCEPTION
      'deidentified anomaly private relation contains a forbidden value column';
  END IF;

  -- The opaque map has one stable identifier per immutable provenance source;
  -- the audit is keyed independently and references the authorization chain.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = anomaly_ids_table_oid
      AND constraint_row.contype = 'p'
      AND constraint_row.conkey = ARRAY[1::smallint]
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = anomaly_ids_table_oid
      AND constraint_row.contype = 'u'
      AND constraint_row.conkey = ARRAY[2::smallint]
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = anomaly_ids_table_oid
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = provenance_table_oid
      AND constraint_row.conkey = ARRAY[2::smallint]
      AND constraint_row.confkey = ARRAY[
        (
          SELECT attribute_row.attnum
          FROM pg_catalog.pg_attribute AS attribute_row
          WHERE attribute_row.attrelid = provenance_table_oid
            AND attribute_row.attname = 'source_id'
        )::smallint
      ]
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'ON DELETE RESTRICT'
  ) THEN
    RAISE EXCEPTION
      'deidentified anomaly opaque-map keys or provenance FK are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = access_events_table_oid
      AND constraint_row.contype = 'p'
      AND constraint_row.conkey = ARRAY[1::smallint]
  ) THEN
    RAISE EXCEPTION 'deidentified anomaly audit primary key is incomplete';
  END IF;

  FOREACH role_name IN ARRAY ARRAY[
    'requested_by_app_user_id',
    'organization_workspace_id',
    'organization_membership_id',
    'project_membership_id',
    'capability_grant_id',
    'project_id'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = access_events_table_oid
        AND constraint_row.contype = 'f'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = access_events_table_oid
              AND attribute_row.attname = role_name
          )::smallint
        ]
    ) THEN
      RAISE EXCEPTION 'deidentified anomaly audit FK is missing: %', role_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = access_events_table_oid
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* $$capability_id[[:space:]]*=[[:space:]]*'view_deidentified_anomalies'$$
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = access_events_table_oid
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* $$access_kind[^']*'directory'[^']*'detail'$$
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = access_events_table_oid
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* $$result_status[^']*'completed'[^']*'not_found'$$
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = access_events_table_oid
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'returned_anomaly_count'
  ) THEN
    RAISE EXCEPTION
      'deidentified anomaly audit value-free CHECK contract is incomplete';
  END IF;

  -- Both relations are forced through RLS.  The only policy is the private
  -- owner policy; the owner role is closed and has no membership in restore.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = anomaly_ids_table_oid
      AND class_row.relrowsecurity
      AND class_row.relforcerowsecurity
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = access_events_table_oid
      AND class_row.relrowsecurity
      AND class_row.relforcerowsecurity
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = anomaly_ids_table_oid
      AND policy_row.polname = 'deidentified_location_anomaly_ids_reader_policy'
      AND policy_row.polcmd = '*'
      AND policy_row.polroles = ARRAY[table_owner::regrole::oid]
      AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) = 'true'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) = 'true'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = access_events_table_oid
      AND policy_row.polname =
        'deidentified_location_anomaly_access_reader_policy'
      AND policy_row.polcmd = '*'
      AND policy_row.polroles = ARRAY[table_owner::regrole::oid]
      AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) = 'true'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) = 'true'
  ) THEN
    RAISE EXCEPTION 'deidentified anomaly private relation RLS is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = anomaly_ids_table_oid
      AND trigger_row.tgname = 'deidentified_location_anomaly_ids_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = access_events_table_oid
      AND trigger_row.tgname = 'deidentified_location_anomaly_access_events_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = access_events_table_oid
      AND trigger_row.tgname = 'deidentified_location_anomaly_access_events_validate'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = provenance_table_oid
      AND trigger_row.tgname =
        'contact_location_provenance_map_deidentified_anomaly'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'deidentified anomaly trigger contract is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname =
        'deidentified_location_anomaly_access_events_project_idx'
  ) THEN
    RAISE EXCEPTION 'deidentified anomaly audit project index is missing';
  END IF;

  -- New functions are volatile because they hold authorization locks and/or
  -- append an audit row.  Their fixed search path is part of the SD boundary.
  FOREACH role_name IN ARRAY ARRAY[
    'app_private.list_authorized_deidentified_location_anomalies_v1(uuid,uuid)',
    'app_private.read_authorized_deidentified_location_anomaly_v1(uuid,uuid,uuid)',
    'app_private.capture_deidentified_location_anomaly_id_v1()',
    'app_private.validate_deidentified_location_anomaly_access_v1()'
  ] LOOP
    IF to_regprocedure(role_name) IS NULL THEN
      RAISE EXCEPTION 'deidentified anomaly function disappeared: %', role_name;
    END IF;

    SELECT
      pg_catalog.pg_get_userbyid(function_row.proowner),
      function_row.proconfig,
      function_row.provolatile,
      function_row.prosecdef
    INTO
      function_owner,
      function_config,
      function_volatility,
      function_security_definer
    FROM pg_catalog.pg_proc AS function_row
    WHERE function_row.oid = to_regprocedure(role_name);

    IF function_owner IS DISTINCT FROM table_owner
      OR function_config IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
      OR function_volatility <> 'v'
      OR NOT function_security_definer
    THEN
      RAISE EXCEPTION
        'deidentified anomaly function security is incorrect: %', role_name;
    END IF;
  END LOOP;

  SELECT pg_catalog.pg_get_functiondef(directory_function)
  INTO STRICT function_source;

  IF function_source !~* 'resolve_management_report_authorization_v1'
    OR function_source !~* 'view_deidentified_anomalies'
    OR function_source !~* 'contact_location_provenance'
    OR function_source !~* 'contact_revisions'
    OR function_source !~* 'current_revision'
    OR function_source !~* 'lifecycle_status'
    OR function_source !~* 'pending_resolution'
    OR function_source !~* 'pending_coordinates'
    OR function_source !~* 'legacy_incomplete'
    OR function_source !~* 'LIMIT[[:space:]]+20'
    OR function_source !~* 'occurred_at_utc[[:space:]]+DESC'
    OR function_source !~* 'anomaly_id[[:space:]]+DESC'
    OR function_source !~* 'returned_anomaly_count'
    OR function_source !~* $$'has_usable_coordinates'$$
    OR function_source ~* 'contact_region_assignments'
    OR function_source ~* 'list_authorized_management_report_snapshots_v1'
    OR function_source ~* 'read_authorized_management_report_snapshot_v1'
    OR function_source ~* 'current_city|interest_report|original_region'
    OR function_source ~* 'protected_report|period_results|cells'
    OR function_source ~* $$'coordinates'$$
    OR function_source ~* $$'latitude'$$
    OR function_source ~* $$'longitude'$$
  THEN
    RAISE EXCEPTION
      'deidentified anomaly directory provenance/privacy contract is incomplete';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(detail_function)
  INTO STRICT function_source;

  IF function_source !~* 'resolve_management_report_authorization_v1'
    OR function_source !~* 'view_deidentified_anomalies'
    OR function_source !~* 'requested_anomaly_id'
    OR function_source !~* 'contact_location_provenance'
    OR function_source !~* 'contact_revisions'
    OR function_source !~* 'current_revision'
    OR function_source !~* 'lifecycle_status'
    OR function_source !~* 'pending_resolution'
    OR function_source !~* 'pending_coordinates'
    OR function_source !~* 'legacy_incomplete'
    OR function_source !~* $$'not_found'$$
    OR function_source !~* $$'coordinates'$$
    OR function_source !~* $$'latitude'$$
    OR function_source !~* $$'longitude'$$
    OR function_source !~* $$'accuracy_meters'$$
    OR function_source !~* 'pg_advisory_xact_lock'
    OR function_source ~* 'contact_region_assignments'
    OR function_source ~* 'list_authorized_management_report_snapshots_v1'
    OR function_source ~* 'read_authorized_management_report_snapshot_v1'
    OR function_source ~* 'current_city|interest_report|original_region'
    OR function_source ~* 'protected_report|period_results|cells'
    OR function_source ~* 'external_identities'
  THEN
    RAISE EXCEPTION
      'deidentified anomaly detail provenance/privacy contract is incomplete';
  END IF;

  -- Authorization must be resolved before the opaque map is inspected.  This
  -- is a static guard against a future existence-leaking lookup being moved
  -- above the capability/membership lock boundary.
  IF strpos(
      lower(function_source),
      'resolve_management_report_authorization_v1'
    ) > strpos(lower(function_source), 'from app_private')
  THEN
    RAISE EXCEPTION
      'deidentified anomaly detail looks up the resource before authorization';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(capture_function)
  INTO STRICT function_source;
  IF function_source !~* 'NEW[.]revision_kind'
    OR function_source !~* 'pending_resolution'
    OR function_source !~* 'pending_coordinates'
    OR function_source !~* 'legacy_incomplete'
    OR function_source !~* 'INSERT[[:space:]]+INTO[[:space:]]+app_private[.]deidentified_location_anomaly_ids'
  THEN
    RAISE EXCEPTION 'deidentified anomaly provenance capture is not narrow';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(validation_function)
  INTO STRICT function_source;
  IF function_source !~* 'authorization_reference_at_utc'
    OR function_source !~* 'capability_id'
    OR function_source !~* 'organization_memberships'
    OR function_source !~* 'project_memberships'
    OR function_source !~* 'management_report_capability_grants'
  THEN
    RAISE EXCEPTION 'deidentified anomaly audit authorization validation is narrow';
  END IF;

  -- No external role receives either private function or private table
  -- access.  Keep this matrix explicit so a later GRANT cannot be hidden by
  -- an inherited role or a broad schema privilege.
  FOREACH role_name IN ARRAY ARRAY[
    'public',
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer',
    'tongxingzhe_management_follow_up_consent_ratio_reader',
    'tongxingzhe_management_consent_ratio_snapshot_release_writer'
  ] LOOP
    IF has_function_privilege(role_name, directory_function, 'EXECUTE')
      OR has_function_privilege(role_name, detail_function, 'EXECUTE')
      OR has_function_privilege(role_name, capture_function, 'EXECUTE')
      OR has_function_privilege(role_name, validation_function, 'EXECUTE')
      OR has_table_privilege(
        role_name,
        anomaly_ids_table_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
      OR has_table_privilege(
        role_name,
        access_events_table_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION
        'forbidden role can access deidentified anomaly contract: %',
        role_name;
    END IF;
  END LOOP;

  IF has_function_privilege(
      'tongxingzhe_runtime',
      resolver_function,
      'EXECUTE'
    )
    OR has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      anomaly_ids_table_oid,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      access_events_table_oid,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      provenance_table_oid,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      contacts_table_oid,
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      revisions_table_oid,
      'SELECT'
    )
  THEN
    RAISE EXCEPTION
      'runtime received direct deidentified anomaly or provenance access';
  END IF;

  -- The existing provenance writer may append accepted revision evidence, but
  -- 6CC must not turn that INSERT seam into a coordinate/source read seam.
  IF has_table_privilege(
      'tongxingzhe_contact_provenance_writer',
      provenance_table_oid,
      'SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = provenance_table_oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND has_column_privilege(
          'tongxingzhe_contact_provenance_writer',
          provenance_table_oid,
          attribute_row.attname,
          'SELECT'
        )
    )
  THEN
    RAISE EXCEPTION
      'provenance writer received direct source or coordinate read access';
  END IF;

  -- The private reader receives only the columns required by the two
  -- SECURITY DEFINER functions; no place/region/source metadata or PII.
  FOREACH role_name IN ARRAY ARRAY[
    'contact_id', 'project_id', 'occurred_at_utc', 'current_revision',
    'lifecycle_status'
  ] LOOP
    IF NOT has_column_privilege(
      table_owner,
      'app_data.contacts',
      role_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'reader is missing contacts column privilege: %', role_name;
    END IF;
  END LOOP;

  FOREACH role_name IN ARRAY ARRAY[
    'contact_id', 'revision_number', 'revision_kind'
  ] LOOP
    IF NOT has_column_privilege(
      table_owner,
      'app_data.contact_revisions',
      role_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION
        'reader is missing contact revisions column privilege: %', role_name;
    END IF;
  END LOOP;

  FOREACH role_name IN ARRAY ARRAY[
    'source_id', 'contact_id', 'revision_number', 'revision_kind',
    'location_kind', 'evidence_kind', 'latitude', 'longitude',
    'accuracy_meters'
  ] LOOP
    IF NOT has_column_privilege(
      table_owner,
      'app_data.contact_location_provenance',
      role_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION
        'reader is missing provenance column privilege: %', role_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = contacts_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND has_column_privilege(
        table_owner,
        contacts_table_oid,
        attribute_row.attname,
        'SELECT'
      )
      AND attribute_row.attname NOT IN (
        'contact_id', 'project_id', 'occurred_at_utc', 'current_revision',
        'lifecycle_status'
      )
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = revisions_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND has_column_privilege(
        table_owner,
        revisions_table_oid,
        attribute_row.attname,
        'SELECT'
      )
      AND attribute_row.attname NOT IN (
        'contact_id', 'revision_number', 'revision_kind'
      )
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = provenance_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND has_column_privilege(
        table_owner,
        provenance_table_oid,
        attribute_row.attname,
        'SELECT'
      )
      AND attribute_row.attname NOT IN (
        'source_id', 'contact_id', 'revision_number', 'revision_kind',
        'location_kind', 'evidence_kind', 'latitude', 'longitude',
        'accuracy_meters'
      )
  ) THEN
    RAISE EXCEPTION 'deidentified anomaly reader received forbidden source columns';
  END IF;

  -- Authorization tables are intentionally column-granted.  A table-level
  -- grant (including a non-SELECT grant) would silently expose fields that
  -- the resolver does not need, so require the exact six-column contract.
  FOR required_column IN
    SELECT *
    FROM (
      VALUES
        (
          'app_users'::text,
          ARRAY['app_user_id', 'status']::text[]
        ),
        (
          'workspaces'::text,
          ARRAY['deleted_at', 'workspace_id', 'workspace_kind']::text[]
        ),
        (
          'projects'::text,
          ARRAY['project_id', 'status', 'workspace_id']::text[]
        ),
        (
          'organization_memberships'::text,
          ARRAY[
            'active_from_utc',
            'app_user_id',
            'inactive_from_utc',
            'organization_membership_id',
            'organization_workspace_id'
          ]::text[]
        ),
        (
          'project_memberships'::text,
          ARRAY[
            'active_from_utc',
            'inactive_from_utc',
            'organization_membership_id',
            'project_id',
            'project_membership_id'
          ]::text[]
        ),
        (
          'management_report_capability_grants'::text,
          ARRAY[
            'active_from_utc',
            'capability_grant_id',
            'capability_id',
            'inactive_from_utc',
            'project_membership_id'
          ]::text[]
        )
    ) AS expected(table_name, expected_columns)
  LOOP
    IF (
      SELECT array_agg(
        column_privilege.column_name::text
        ORDER BY column_privilege.column_name
      )
      FROM information_schema.column_privileges AS column_privilege
      WHERE column_privilege.grantee = table_owner
        AND column_privilege.table_schema = 'app_data'
        AND column_privilege.table_name = required_column.table_name
        AND column_privilege.privilege_type = 'SELECT'
    ) IS DISTINCT FROM required_column.expected_columns
    THEN
      RAISE EXCEPTION
        'deidentified anomaly reader authorization columns are not exact: %',
        required_column.table_name;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM information_schema.column_privileges AS column_privilege
      WHERE column_privilege.grantee = table_owner
        AND column_privilege.table_schema = 'app_data'
        AND column_privilege.table_name = required_column.table_name
        AND column_privilege.privilege_type <> 'SELECT'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.table_privileges AS table_privilege
      WHERE table_privilege.grantee = table_owner
        AND table_privilege.table_schema = 'app_data'
        AND table_privilege.table_name = required_column.table_name
    ) THEN
      RAISE EXCEPTION
        'deidentified anomaly reader has broad authorization-table privilege: %',
        required_column.table_name;
    END IF;
  END LOOP;

  IF NOT has_function_privilege(table_owner, resolver_function, 'EXECUTE')
    OR NOT has_function_privilege(table_owner, directory_function, 'EXECUTE')
    OR NOT has_function_privilege(table_owner, detail_function, 'EXECUTE')
    OR NOT has_table_privilege(table_owner, access_events_table_oid, 'INSERT')
  THEN
    RAISE EXCEPTION 'deidentified anomaly reader execution boundary is incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0081_authorized_management_deidentified_location_anomaly_read'
  ) <> 1 THEN
    RAISE EXCEPTION
      'deidentified location anomaly read migration was not recorded once';
  END IF;
END
$check$;
