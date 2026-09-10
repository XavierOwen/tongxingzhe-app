\set ON_ERROR_STOP on

DO $check$
DECLARE
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_application_request_claims'
  );
  tombstones_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_application_request_tombstones'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_application_audit_events'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_approve regprocedure := pg_catalog.to_regprocedure(
    'app_private.approve_organization_shareable_join_application_v1(uuid,uuid,uuid)'
  );
  bridge_approve regprocedure := pg_catalog.to_regprocedure(
    'app_data.approve_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)'
  );
  trusted_owner oid;
  runtime_role oid;
  actual_result_names text[];
  actual_result_types text[];
  function_oid oid;
  private_definition text;
  bridge_definition text;
BEGIN
  IF claims_table IS NULL
    OR tombstones_table IS NULL
    OR audit_table IS NULL
    OR membership_validator IS NULL
    OR private_approve IS NULL
    OR bridge_approve IS NULL
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval objects are incomplete';
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
      'organization shareable join application approval owner cannot be runtime';
  END IF;

  IF pg_catalog.pg_get_function_identity_arguments(private_approve)
      IS DISTINCT FROM
      'trusted_actor_app_user_id uuid, requested_application_id uuid, requested_organization_workspace_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(bridge_approve)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_application_id uuid, requested_organization_workspace_id uuid'
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval signatures drifted';
  END IF;

  FOR function_oid IN
    SELECT unnest(ARRAY[private_approve, bridge_approve]::oid[])
  LOOP
    SELECT
      array_agg(argument_row.argument_name ORDER BY argument_row.ordinality),
      array_agg(
        pg_catalog.format_type(argument_row.argument_type, NULL)
        ORDER BY argument_row.ordinality
      )
    INTO actual_result_names, actual_result_types
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
    WHERE procedure_row.oid = function_oid
      AND argument_row.argument_mode = 't';

    IF actual_result_names IS DISTINCT FROM ARRAY[
        'organization_shareable_join_application_contract_id',
        'application_id',
        'organization_workspace_id',
        'organization_membership_id',
        'approved_at_utc'
      ]::text[]
      OR actual_result_types IS DISTINCT FROM ARRAY[
        'text',
        'uuid',
        'uuid',
        'uuid',
        'timestamp with time zone'
      ]::text[]
    THEN
      RAISE EXCEPTION
        'organization shareable join application approval result drifted';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_language AS language_row
      ON language_row.oid = procedure_row.prolang
    WHERE procedure_row.oid IN (private_approve, bridge_approve)
      AND (
        procedure_row.proowner <> trusted_owner
        OR NOT procedure_row.prosecdef
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
        OR language_row.lanname <> 'plpgsql'
        OR NOT procedure_row.proretset
        OR octet_length(procedure_row.proname) > 63
      )
  )
    OR (
      SELECT octet_length(procedure_row.proname)
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid = bridge_approve
    ) <> 63
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval boundary drifted';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', bridge_approve, 'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', private_approve, 'EXECUTE'
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
      WHERE procedure_row.oid IN (private_approve, bridge_approve)
        AND (
          privilege_row.grantee = 0
          OR privilege_row.grantee NOT IN (trusted_owner, runtime_role)
          OR privilege_row.privilege_type <> 'EXECUTE'
          OR (
            privilege_row.grantee = runtime_role
            AND procedure_row.oid <> bridge_approve
          )
        )
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval ACL is not minimal';
  END IF;

  IF pg_catalog.has_schema_privilege(
      'tongxingzhe_runtime', 'app_private', 'USAGE'
    )
    OR EXISTS (
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
          tombstones_table,
          audit_table,
          'app_data.external_identities'::regclass,
          'app_data.app_users'::regclass,
          'app_data.workspaces'::regclass,
          'app_data.organization_memberships'::regclass,
          'app_data.organization_owner_assignments'::regclass
        )
        AND privilege_row.grantee IN (0, runtime_role)
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval facts are exposed';
  END IF;

  private_definition := pg_catalog.pg_get_functiondef(private_approve);
  bridge_definition := pg_catalog.pg_get_functiondef(bridge_approve);

  -- The initial claim read only chooses the reduced or full lock set. All
  -- observable request classification follows the locked current-owner gate.
  IF strpos(private_definition,
      'organization-shareable-join-application-request:') = 0
    OR strpos(private_definition, 'SELECT DISTINCT app_user_key') = 0
    OR strpos(private_definition, 'ORDER BY app_user_key') = 0
    OR strpos(private_definition, 'FOR UPDATE') = 0
    OR strpos(private_definition,
      'app_private.lock_organization_governance_v1') = 0
    OR strpos(private_definition, 'organization-membership:') = 0
    OR NOT (
      strpos(private_definition,
        'organization-shareable-join-application-request:')
        < strpos(private_definition, 'INTO initial_application_row')
      AND strpos(private_definition, 'INTO initial_application_row')
        < strpos(private_definition, 'SELECT DISTINCT app_user_key')
      AND strpos(private_definition, 'SELECT DISTINCT app_user_key')
        < strpos(private_definition, 'ORDER BY app_user_key')
      AND strpos(private_definition, 'ORDER BY app_user_key')
        < strpos(private_definition, 'FOR UPDATE')
      AND strpos(private_definition, 'FOR UPDATE')
        < strpos(private_definition,
          'app_private.lock_organization_governance_v1')
      AND strpos(private_definition,
        'app_private.lock_organization_governance_v1')
        < strpos(private_definition, 'organization-membership:')
      AND strpos(private_definition, 'organization-membership:')
        < strpos(private_definition, 'INTO actor_status')
      AND strpos(private_definition, 'INTO actor_status')
        < strpos(private_definition, 'INTO workspace_kind')
      AND strpos(private_definition, 'INTO workspace_kind')
        < strpos(private_definition, 'INTO actor_owner_periods')
      AND strpos(private_definition, 'INTO actor_owner_periods')
        < strpos(private_definition, 'INTO application_tombstone_found')
      AND strpos(private_definition, 'INTO application_tombstone_found')
        < strpos(private_definition, 'INTO application_row')
      AND strpos(private_definition, 'INTO application_row')
        < strpos(private_definition, 'INTO applicant_status')
      AND strpos(private_definition, 'INTO applicant_status')
        < strpos(private_definition, 'INTO applicant_membership_periods')
      AND strpos(private_definition, 'INTO applicant_membership_periods')
        < strpos(private_definition, 'clock_timestamp()')
    )
    OR private_definition !~
      'initial_application_row\.approved_at_utc IS NULL'
    OR private_definition !~
      'initial_application_row\.approved_organization_membership_id IS NULL'
    OR private_definition !~
      'initial_application_row\.applicant_app_user_id IS NOT NULL'
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval lock order drifted';
  END IF;

  IF (
    char_length(private_definition)
      - char_length(replace(private_definition, 'clock_timestamp()', ''))
  ) / char_length('clock_timestamp()') <> 1
    OR private_definition ~*
      '(transaction_timestamp|statement_timestamp|current_timestamp)[[:space:]]*[(]?'
    OR private_definition ~* '\mnow[[:space:]]*[(]'
    OR NOT (
      strpos(private_definition, 'clock_timestamp()')
        < strpos(private_definition,
          'IF actor_status IS DISTINCT FROM ''active''')
      AND strpos(private_definition,
          'IF actor_status IS DISTINCT FROM ''active''')
        < strpos(private_definition,
          'IF application_tombstone_found')
      AND strpos(private_definition,
          'IF application_tombstone_found')
        < strpos(private_definition,
          'IF application_row.approved_at_utc IS NOT NULL')
      AND strpos(private_definition,
          'IF application_row.approved_at_utc IS NOT NULL')
        < strpos(private_definition, 'IF workspace_deleted_at IS NOT NULL')
      AND strpos(private_definition, 'IF workspace_deleted_at IS NOT NULL')
        < strpos(private_definition,
          'INSERT INTO app_data.organization_memberships')
      AND strpos(private_definition,
          'INSERT INTO app_data.organization_memberships')
        < strpos(private_definition,
          'UPDATE app_private.organization_shareable_join_application_request_claims')
      AND strpos(private_definition,
          'UPDATE app_private.organization_shareable_join_application_request_claims')
        < strpos(private_definition,
          'INSERT INTO app_private.organization_shareable_join_application_audit_events')
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval clock or classification drifted';
  END IF;

  IF private_definition !~
      'workspace_kind IS DISTINCT FROM ''organization'''
    OR private_definition !~
      'approval_time <@ ANY \(actor_owner_periods\)'
    OR private_definition !~ 'application_tombstone_found'
    OR private_definition !~ 'NOT application_found'
    OR private_definition !~
      'application_row\.organization_workspace_id IS DISTINCT FROM[[:space:]]+requested_organization_workspace_id'
    OR private_definition !~ 'workspace_deleted_at IS NOT NULL'
    OR private_definition !~
      'application_row\.applicant_app_user_id IS NULL'
    OR private_definition !~ 'applicant_status IS DISTINCT FROM ''active'''
    OR private_definition !~
      'approval_time >= application_row\.expires_at_utc'
    OR private_definition !~
      'approval_time <@ ANY \(applicant_membership_periods\)'
    OR private_definition !~ 'organization-shareable-join-application:v1'
    OR private_definition !~ 'invalid organization shareable join request'
    OR private_definition !~ 'organization shareable join forbidden'
    OR private_definition ~* 'idempotency conflict'
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval policy drifted';
  END IF;

  -- Only the membership insert's two expected validator failures are mapped.
  IF private_definition !~
      'WHEN SQLSTATE ''22023'' OR SQLSTATE ''23P01'' THEN'
    OR private_definition ~* 'WHEN[[:space:]]+OTHERS'
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'INSERT INTO app_data.organization_memberships',
          ''
        ))
    ) / char_length('INSERT INTO app_data.organization_memberships') <> 1
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'UPDATE app_private.organization_shareable_join_application_request_claims',
          ''
        ))
    ) / char_length(
      'UPDATE app_private.organization_shareable_join_application_request_claims'
    ) <> 1
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'INSERT INTO app_private.organization_shareable_join_application_audit_events',
          ''
        ))
    ) / char_length(
      'INSERT INTO app_private.organization_shareable_join_application_audit_events'
    ) <> 1
    OR private_definition ~*
      '(insert[[:space:]]+into|update|delete[[:space:]]+from|merge[[:space:]]+into|truncate)[[:space:]]+app_data\.(project_memberships|organization_owner_assignments|management_report_capability_grants)'
    OR private_definition ~*
      '(update|delete[[:space:]]+from|merge[[:space:]]+into|truncate)[[:space:]]+app_data\.organization_memberships'
    OR private_definition ~*
      '(insert[[:space:]]+into|delete[[:space:]]+from|merge[[:space:]]+into|truncate)[[:space:]]+app_private\.organization_shareable_join_application_request_claims'
    OR private_definition ~*
      '(update|delete[[:space:]]+from|merge[[:space:]]+into|truncate)[[:space:]]+app_private\.organization_shareable_join_application_audit_events'
    OR private_definition ~*
      'organization-shareable-join-link-request:'
    OR private_definition ~*
      'organization_shareable_join_link_(request_claims|request_tombstones|audit_events)'
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval write boundary drifted';
  END IF;

  IF bridge_definition !~ 'invalid organization shareable join identity'
    OR bridge_definition !~ 'organization shareable join forbidden'
    OR bridge_definition !~ 'identity_row\.issuer = trusted_issuer'
    OR bridge_definition !~ 'identity_row\.subject = trusted_subject'
    OR bridge_definition !~ 'app_user\.status = ''active'''
    OR bridge_definition !~
      'app_private\.approve_organization_shareable_join_application_v1'
    OR bridge_definition ~* 'btrim[[:space:]]*[(]identity_row\.'
    OR bridge_definition ~*
      '\m(insert|update|delete|merge|truncate|pg_advisory_xact_lock)\M'
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval bridge drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0094_organization_shareable_join_application_approval'
  ) <> 1
  THEN
    RAISE EXCEPTION
      'organization shareable join application approval migration was not recorded once';
  END IF;
END
$check$;
