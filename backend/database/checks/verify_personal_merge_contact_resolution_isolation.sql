\set ON_ERROR_STOP on
DO $check$
DECLARE
  confirm regprocedure := 'app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  expected_owner oid;
  source text;
  isolation_guard constant text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'pending contact resolution confirmation requires read committed';
  END IF;
$guard$;
  guard_position integer;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version = '0132_personal_merge_contact_resolution_isolation') <> 1
  THEN RAISE EXCEPTION '0132 resolution isolation migration is missing'; END IF;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
    WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = confirm AND proowner = expected_owner AND prosecdef AND NOT proretset
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[]
      AND provolatile = 'v'::"char" AND prorettype = 'timestamptz'::regtype
      AND proargnames = ARRAY['trusted_app_user_id','trusted_workspace_id','trusted_project_id','requested_request_id',
        'requested_generation_id','expected_known_fact_fingerprint','expected_pending_fingerprint',
        'expected_resolution_fingerprint','requested_assignments','requested_current_choices']::text[])
    OR has_function_privilege('public',confirm,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',confirm,'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) acl
      WHERE f.oid = confirm AND acl.grantee <> f.proowner)
  THEN RAISE EXCEPTION '0132 private confirmation function signature, owner, security or ACL drift'; END IF;

  SELECT prosrc INTO STRICT source FROM pg_proc WHERE oid = confirm;
  guard_position := position(isolation_guard IN source);
  IF guard_position = 0
    OR length(source) - length(replace(source, isolation_guard, '')) <> length(isolation_guard)
    OR position('pg_advisory_xact_lock' IN source) <= guard_position
    OR position('SELECT * INTO request_row FROM app_private.personal_merge_contact_resolution_requests_v1' IN source) <= guard_position
    OR position('INSERT INTO app_private.personal_merge_contact_resolution_requests_v1' IN source) <= guard_position
  THEN RAISE EXCEPTION '0132 read-committed guard must occur once before parent locking and receipt access'; END IF;
END
$check$;
