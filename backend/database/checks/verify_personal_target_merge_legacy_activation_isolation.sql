\set ON_ERROR_STOP on
DO $check$
DECLARE
  activation regprocedure := 'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'::regprocedure;
  body text;
  entry_anchor text := $entry$DECLARE
  created_generation_id uuid;
BEGIN
$entry$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'legacy personal target merge generation activation requires read committed';
  END IF;
$guard$;
  guard_position integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0148_personal_target_merge_legacy_activation_isolation') THEN
    RAISE EXCEPTION '0148 legacy activation isolation migration is missing';
  END IF;
  SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = activation;
  guard_position := position(guard IN body);
  IF position(entry_anchor || guard IN body) <> 2
    OR length(body) - length(replace(body, guard, '')) <> length(guard)
    OR position('UPDATE app_private.personal_target_merge_generation_fence_v1' IN body) <= guard_position
    OR has_function_privilege('public', activation, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', activation, 'EXECUTE') THEN
    RAISE EXCEPTION '0148 legacy activation isolation order or private ACL drift';
  END IF;
END
$check$;
