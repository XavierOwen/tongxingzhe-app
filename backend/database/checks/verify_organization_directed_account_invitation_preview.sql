\set ON_ERROR_STOP on

DO $check$
DECLARE
  preview_reader regprocedure := pg_catalog.to_regprocedure(
    'app_data.preview_organization_directed_invitation_for_identity_v1(text,text,uuid)'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.organization_directed_account_invitation_request_claims'
  );
  trusted_owner oid;
  runtime_role oid;
  actual_input_names text[];
  actual_output_names text[];
  actual_output_types text[];
  function_definition text;
BEGIN
  IF preview_reader IS NULL
    OR membership_validator IS NULL
    OR claims_table IS NULL
  THEN
    RAISE EXCEPTION
      'organization directed invitation preview objects are incomplete';
  END IF;

  SELECT procedure_row.proowner
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = membership_validator;

  SELECT role_row.oid
  INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  IF trusted_owner = runtime_role THEN
    RAISE EXCEPTION
      'organization directed invitation preview owner cannot be runtime';
  END IF;

  SELECT
    procedure_row.proargnames[1:3],
    array_agg(argument_row.argument_name ORDER BY argument_row.ordinality)
      FILTER (WHERE argument_row.argument_mode = 't'),
    array_agg(
      pg_catalog.format_type(argument_row.argument_type, NULL)
      ORDER BY argument_row.ordinality
    ) FILTER (WHERE argument_row.argument_mode = 't')
  INTO actual_input_names, actual_output_names, actual_output_types
  FROM pg_catalog.pg_proc AS procedure_row
  CROSS JOIN LATERAL unnest(
    procedure_row.proallargtypes,
    procedure_row.proargmodes,
    procedure_row.proargnames
  ) WITH ORDINALITY AS argument_row(
    argument_type,
    argument_mode,
    argument_name,
    ordinality
  )
  WHERE procedure_row.oid = preview_reader
  GROUP BY procedure_row.proargnames;

  IF actual_input_names IS DISTINCT FROM ARRAY[
      'trusted_issuer',
      'trusted_subject',
      'requested_invitation_id'
    ]::text[]
    OR actual_output_names IS DISTINCT FROM ARRAY[
      'organization_invitation_preview_contract_id',
      'invitation_id',
      'organization_name',
      'expires_at_utc'
    ]::text[]
    OR actual_output_types IS DISTINCT FROM ARRAY[
      'text',
      'uuid',
      'text',
      'timestamp with time zone'
    ]::text[]
  THEN
    RAISE EXCEPTION
      'organization directed invitation preview signature drifted';
  END IF;

  IF (
    SELECT
      procedure_row.proowner <> trusted_owner
      OR procedure_row.proname IS DISTINCT FROM
        'preview_organization_directed_invitation_for_identity_v1'
      OR octet_length(procedure_row.proname) > 63
      OR NOT procedure_row.proretset
      OR NOT procedure_row.prosecdef
      OR procedure_row.provolatile <> 'v'
      OR language_row.lanname <> 'plpgsql'
      OR procedure_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_language AS language_row
      ON language_row.oid = procedure_row.prolang
    WHERE procedure_row.oid = preview_reader
  ) THEN
    RAISE EXCEPTION
      'organization directed invitation preview boundary drifted';
  END IF;

  -- PUBLIC cannot execute it. Runtime receives only EXECUTE on the bridge.
  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', preview_reader, 'EXECUTE'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(
          procedure_row.proacl,
          pg_catalog.acldefault('f', procedure_row.proowner)
        )
      ) AS privilege_row
      WHERE procedure_row.oid = preview_reader
        AND (
          privilege_row.grantee = 0
          OR privilege_row.grantee NOT IN (trusted_owner, runtime_role)
          OR privilege_row.privilege_type <> 'EXECUTE'
        )
    )
  THEN
    RAISE EXCEPTION
      'organization directed invitation preview function ACL is incorrect';
  END IF;

  -- Neither runtime nor PUBLIC can bypass the bridge and inspect source rows.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(
        relation_row.relacl,
        pg_catalog.acldefault('r', relation_row.relowner)
      )
    ) AS privilege_row
    WHERE relation_row.oid IN (
        claims_table,
        'app_data.external_identities'::regclass,
        'app_data.app_users'::regclass,
        'app_data.workspaces'::regclass,
        'app_data.organization_memberships'::regclass
      )
      AND privilege_row.grantee IN (0, runtime_role)
  ) THEN
    RAISE EXCEPTION
      'organization directed invitation preview exposed source tables';
  END IF;

  function_definition := pg_catalog.pg_get_functiondef(preview_reader);

  IF (
    char_length(function_definition)
      - char_length(replace(function_definition, 'clock_timestamp()', ''))
  ) / char_length('clock_timestamp()') <> 1
    OR (
      char_length(lower(function_definition))
        - char_length(
          replace(lower(function_definition), 'return query', '')
        )
    ) / char_length('return query') <> 1
    OR function_definition !~
      'app_private\.organization_directed_account_invitation_request_claims'
    OR function_definition !~ 'app_data\.external_identities'
    OR function_definition !~ 'app_data\.app_users'
    OR function_definition !~ 'app_data\.workspaces'
    OR function_definition !~ 'app_data\.organization_memberships'
    OR function_definition !~ 'organization-directed-account-invitation-preview:v1'
    OR function_definition !~ 'organization invitation forbidden'
    OR function_definition ~*
      '\m(insert|update|delete|merge|truncate)\M'
    OR function_definition ~*
      'pg_advisory|FOR[[:space:]]+UPDATE|lock_organization'
    OR function_definition ~*
      'organization_directed_account_invitation_(request_tombstones|audit_events)'
    OR function_definition ~*
      'app_data\.(organization_owner_assignments|project_memberships|projects)'
  THEN
    RAISE EXCEPTION
      'organization directed invitation preview query scope drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0091_organization_directed_account_invitation_preview'
  ) <> 1 THEN
    RAISE EXCEPTION
      'organization directed invitation preview migration was not recorded once';
  END IF;
END
$check$;
