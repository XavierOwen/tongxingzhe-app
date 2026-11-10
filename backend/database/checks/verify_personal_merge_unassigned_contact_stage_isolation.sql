\set ON_ERROR_STOP on
DO $check$
DECLARE
  stage regprocedure := 'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)'::regprocedure;
  body text;
  validation_tail text := $validation$    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid unassigned contact request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'unassigned contact staging requires read committed';
  END IF;
$guard$;
  guard_position integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0150_personal_merge_unassigned_contact_stage_isolation') THEN
    RAISE EXCEPTION '0150 unassigned contact staging isolation migration is missing';
  END IF;
  SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = stage;
  guard_position := position(guard IN body);
  IF position(validation_tail || guard || '  PERFORM pg_advisory_xact_lock(hashtextextended(' IN body) = 0
    OR length(body) - length(replace(body, guard, '')) <> length(guard)
    OR position('acquire_personal_target_merge_generation_fence_v1' IN body) <= guard_position
    OR position('read_known_source_personal_merge_split_plan_v1' IN body) <= guard_position
    OR has_function_privilege('public', stage, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', stage, 'EXECUTE') THEN
    RAISE EXCEPTION '0150 unassigned contact staging isolation order or private ACL drift';
  END IF;
END
$check$;
