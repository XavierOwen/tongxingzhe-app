\set ON_ERROR_STOP on
DO $check$
DECLARE function_oid oid; function_name text; trusted_owner oid;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version='0109_organization_purge_finalizer') <> 1 THEN
    RAISE EXCEPTION '0109 migration must be recorded exactly once';
  END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid='app_private.validate_organization_membership_v1()'::regprocedure;
  FOREACH function_name IN ARRAY ARRAY[
    'app_private.finalize_organization_purge_v1(uuid,uuid)',
    'app_private.record_organization_purge_failed_v1(uuid,uuid)',
    'app_private.organization_purge_requests_v1(uuid)'] LOOP
    function_oid:=function_name::regprocedure;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=function_oid
        AND proowner=trusted_owner AND prosecdef AND provolatile='v'
        AND proconfig=ARRAY['search_path=pg_catalog']::text[])
      OR has_function_privilege('tongxingzhe_runtime',function_oid,'EXECUTE')
      OR EXISTS (SELECT 1 FROM aclexplode(coalesce(
        (SELECT proacl FROM pg_proc WHERE oid=function_oid),acldefault('f',trusted_owner))) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
    THEN RAISE EXCEPTION '0109 trusted owner/security/ACL drift: %',function_name; END IF;
  END LOOP;
  IF pg_get_function_result('app_private.finalize_organization_purge_v1(uuid,uuid)'::regprocedure)
      IS DISTINCT FROM 'TABLE(deletion_request_id uuid, purge_completed_at_utc timestamp with time zone)'
    OR pg_get_function_result('app_private.record_organization_purge_failed_v1(uuid,uuid)'::regprocedure)
      IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION '0109 result contract drift'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid='app_private.organization_deletion_current'::regclass
      AND conname='organization_deletion_current_state_check'
      AND pg_get_constraintdef(oid) LIKE '%purging%'
      AND pg_get_constraintdef(oid) LIKE '%purge_failed%') THEN
    RAISE EXCEPTION '0109 lifecycle constraint drift';
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations) THEN
    RAISE EXCEPTION '0109 transient authorizations survived a transaction';
  END IF;
END
$check$;

-- Isolation is checked before any request collection or business mutation.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $isolation$
DECLARE actual_state text; actual_message text;
BEGIN
  BEGIN
    PERFORM app_private.finalize_organization_purge_v1(gen_random_uuid(),gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '55000' OR actual_message IS DISTINCT FROM
      'organization purge requires read committed' THEN RAISE EXCEPTION '0109 isolation contract drift'; END IF;
  actual_state:=NULL; actual_message:=NULL;
  BEGIN
    PERFORM app_private.record_organization_purge_failed_v1(gen_random_uuid(),gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '55000' OR actual_message IS DISTINCT FROM
      'organization purge failure requires read committed' THEN RAISE EXCEPTION '0109 failure isolation drift'; END IF;
END
$isolation$;
ROLLBACK;
