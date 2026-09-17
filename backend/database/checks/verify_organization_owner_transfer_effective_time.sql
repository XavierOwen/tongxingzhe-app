\set ON_ERROR_STOP on

DO $check$
DECLARE
  writer regprocedure := 'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  definition text := pg_get_functiondef(writer);
  actor_guard integer := strpos(definition, 'IF actor_owner_assignment_row.active_from_utc >= effective_time');
  target_guard integer := strpos(definition, 'OR target_membership_row.active_from_utc > effective_time');
  write_position integer := strpos(definition, 'INSERT INTO app_data.organization_owner_assignments');
  trusted_owner oid;
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0098_organization_owner_transfer_effective_time') <> 1
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = writer AND proowner = trusted_owner
      AND prosecdef AND provolatile = 'v' AND proconfig = ARRAY['search_path=pg_catalog']::text[])
    OR has_function_privilege('tongxingzhe_runtime', writer, 'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc AS p CROSS JOIN LATERAL
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
      WHERE p.oid = writer AND a.grantee = 0)
  THEN RAISE EXCEPTION '0098 migration or shared writer security boundary drift'; END IF;

  IF regexp_count(definition, 'IF actor_owner_assignment_row[.]active_from_utc >= effective_time') <> 1
    OR regexp_count(definition, 'OR target_membership_row[.]active_from_utc > effective_time') <> 1
    OR actor_guard <= strpos(definition, 'effective_time := transaction_timestamp()')
    OR strpos(definition, 'effective_time := transaction_timestamp()') <= strpos(definition, 'FOR membership_lock_row IN')
    OR actor_guard <= strpos(definition, 'MESSAGE = ''organization owner transfer target already owner''')
    OR target_guard <= actor_guard OR write_position <= target_guard
    OR strpos(definition, 'new_owner_assignment_id := gen_random_uuid()') <= target_guard
    OR substr(definition, target_guard, write_position - target_guard)
      NOT LIKE '%ERRCODE = ''42501''%MESSAGE = ''organization owner transfer forbidden''%'
    OR regexp_count(definition, '@>[[:space:]]*authorization_time') <> 4
    OR regexp_count(definition, 'authorization_time[[:space:]]*:[=][[:space:]]*clock_timestamp[[:space:]]*[(][)]') <> 1
    OR regexp_count(definition, 'effective_time[[:space:]]*:[=][[:space:]]*transaction_timestamp[[:space:]]*[(][)]') <> 1
    OR regexp_count(definition, 'OR target_membership_row[.]inactive_from_utc IS NOT NULL') <> 1
  THEN RAISE EXCEPTION '0098 first-execution effective-time qualification or existing temporal contract drift'; END IF;
END
$check$;
