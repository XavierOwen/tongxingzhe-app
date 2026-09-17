\set ON_ERROR_STOP on

DO $check$
DECLARE
  writer regprocedure := 'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  bridge regprocedure := 'app_data.transfer_organization_owner_for_identity_v1(text,text,uuid,uuid,uuid)'::regprocedure;
  definition text := pg_get_functiondef(writer);
  trusted_owner oid;
  guard_position integer := strpos(definition, 'OR target_membership_row.inactive_from_utc IS NOT NULL');
  target_read_position integer := strpos(definition, '-- Re-read the target membership and account after all locks.');
  insert_position integer := strpos(definition, 'INSERT INTO app_data.organization_owner_assignments');
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0097_organization_owner_transfer_finite_parent') <> 1
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = writer AND proowner = trusted_owner
      AND prosecdef AND provolatile = 'v' AND proconfig = ARRAY['search_path=pg_catalog']::text[])
    OR has_function_privilege('tongxingzhe_runtime', writer, 'EXECUTE')
    OR NOT has_function_privilege('tongxingzhe_runtime', bridge, 'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc AS p CROSS JOIN LATERAL
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
      WHERE p.oid IN (writer, bridge) AND a.grantee = 0)
  THEN RAISE EXCEPTION '0097 migration or existing function security boundary drift'; END IF;

  IF regexp_count(definition, 'OR target_membership_row[.]inactive_from_utc IS NOT NULL') <> 1
    OR guard_position <= target_read_position
    OR target_read_position <= strpos(definition, 'authorization_time := clock_timestamp()')
    OR strpos(definition, 'authorization_time := clock_timestamp()') <= strpos(definition, 'FOR membership_lock_row IN')
    OR insert_position <= guard_position
    OR substr(definition, target_read_position, insert_position - target_read_position)
      NOT LIKE '%ERRCODE = ''42501''%MESSAGE = ''organization owner transfer forbidden''%'
    OR regexp_count(definition, '@>[[:space:]]*authorization_time') <> 4
    OR regexp_count(definition, 'effective_time[[:space:]]*:[=][[:space:]]*transaction_timestamp[[:space:]]*[(][)]') <> 1
    OR substr(definition, insert_position) NOT LIKE '%effective_time,%NULL%UPDATE app_data.organization_owner_assignments%'
  THEN RAISE EXCEPTION '0097 first-execution finite-parent guard or existing handoff contract drift'; END IF;
END
$check$;
