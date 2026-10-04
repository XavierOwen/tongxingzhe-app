\set ON_ERROR_STOP on

DO $check$
DECLARE
  function_oid oid;
  function_definition text;
  owner_oid oid;
  constraint_definition text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0105_organization_deletion_purge_due') <> 1 THEN
    RAISE EXCEPTION '0105 migration not recorded exactly once';
  END IF;

  SELECT procedure.oid, procedure.proowner
  INTO STRICT function_oid, owner_oid
  FROM pg_catalog.pg_proc AS procedure
  WHERE procedure.oid =
    'app_private.mark_organization_deletion_purge_due_v1(uuid)'::regprocedure;

  IF owner_oid IS DISTINCT FROM (
      SELECT proowner FROM pg_catalog.pg_proc
      WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure
    )
    OR NOT (SELECT prosecdef AND provolatile = 'v'
        AND proconfig = ARRAY['search_path=pg_catalog']::text[]
      FROM pg_catalog.pg_proc WHERE oid = function_oid)
    OR has_function_privilege('tongxingzhe_runtime', function_oid, 'EXECUTE')
    OR EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(coalesce(
        (SELECT proacl FROM pg_catalog.pg_proc WHERE oid = function_oid),
        pg_catalog.acldefault('f', owner_oid)
      )) AS acl WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    )
  THEN
    RAISE EXCEPTION '0105 purge-due function owner, security, or ACL drift';
  END IF;

  IF pg_get_function_result(function_oid) IS DISTINCT FROM 'text' THEN
    RAISE EXCEPTION '0105 purge-due function result drift';
  END IF;

  SELECT regexp_replace(pg_catalog.pg_get_functiondef(function_oid), '\s+', ' ', 'g')
  INTO STRICT function_definition;
  IF strpos(function_definition, 'lock_organization_governance_v1') = 0
    OR strpos(function_definition, 'FOR UPDATE') = 0
    OR strpos(function_definition, 'clock_timestamp()') = 0
    OR strpos(function_definition, 'organization_deletion_current') = 0
    OR strpos(function_definition, 'organization_deletion_request_claims') = 0
    OR strpos(function_definition, 'claim.request_id = attempt_row.deletion_request_id') = 0
    OR strpos(function_definition, 'claim.purge_after_utc = attempt_row.purge_after_utc') = 0
    OR strpos(function_definition, 'attempt_row.restored_at_utc IS NOT NULL') = 0
    OR strpos(function_definition, '720 hours') = 0
    OR strpos(function_definition, 'purge_due') = 0
    OR strpos(function_definition, 'reference_time < attempt_row.purge_after_utc') = 0
    OR strpos(function_definition, 'organization_deletion_audit_events') > 0
    OR strpos(function_definition, 'organization_deletion_restore_claims') > 0
  THEN
    RAISE EXCEPTION '0105 purge-due lock, clock, or no-claim contract drift';
  END IF;

  SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
  INTO STRICT constraint_definition
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.conrelid =
      'app_private.organization_deletion_current'::regclass
    AND constraint_row.conname = 'organization_deletion_current_state_check';
  IF strpos(constraint_definition, 'purge_due') = 0
    OR strpos(constraint_definition, 'restored_at_utc IS NULL') = 0
    OR strpos(constraint_definition, 'restored_at_utc IS NOT NULL') = 0
  THEN
    RAISE EXCEPTION '0105 lifecycle state constraint drift';
  END IF;
END
$check$;
