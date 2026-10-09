\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  runtime_role oid;
  retention_action oid := 'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)'::regprocedure;
  configure_policy oid := 'app_data.configure_promotion_target_retention_policy(uuid,uuid,uuid,integer)'::regprocedure;
  acquire_fence oid := 'app_private.acquire_personal_target_merge_generation_fence_v1()'::regprocedure;
  action_definition text;
  policy_definition text;
  action_advisory_position integer;
  action_replay_position integer;
  action_fence_position integer;
  action_update_position integer;
  action_clock_position integer;
  action_fresh_auth_position integer;
  action_due_position integer;
  policy_auth_position integer;
  policy_fence_position integer;
  policy_fresh_auth_position integer;
  policy_upsert_position integer;
BEGIN
  SELECT oid INTO STRICT runtime_role FROM pg_catalog.pg_roles
  WHERE rolname = 'tongxingzhe_runtime';
  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid = retention_action AND prosecdef AND provolatile = 'v'
      AND proconfig @> ARRAY['search_path=pg_catalog, app_data']
      AND proowner = trusted_owner
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid = configure_policy AND prosecdef AND provolatile = 'v'
      AND proconfig @> ARRAY['search_path=pg_catalog, app_data']
      AND proowner = trusted_owner
  ) THEN
    RAISE EXCEPTION 'retention writers have unsafe function security or owner';
  END IF;

  IF (SELECT proowner FROM pg_catalog.pg_proc WHERE oid = acquire_fence)
      IS DISTINCT FROM trusted_owner
  THEN
    RAISE EXCEPTION 'retention writer or fence owner drifted';
  END IF;

  IF NOT has_function_privilege(runtime_role, retention_action, 'EXECUTE')
    OR has_function_privilege('public', retention_action, 'EXECUTE')
    OR NOT has_function_privilege(runtime_role, configure_policy, 'EXECUTE')
    OR has_function_privilege('public', configure_policy, 'EXECUTE')
    OR NOT has_function_privilege(trusted_owner, acquire_fence, 'EXECUTE')
    OR has_function_privilege('public', acquire_fence, 'EXECUTE')
    OR has_function_privilege(runtime_role, acquire_fence, 'EXECUTE')
    OR has_function_privilege(runtime_role,
      'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)',
      'EXECUTE')
    OR has_table_privilege(runtime_role,
      'app_data.promotion_target_retention_policies', 'SELECT,INSERT,UPDATE,DELETE')
    OR has_table_privilege(runtime_role,
      'app_data.promotion_target_retention_events', 'SELECT,INSERT,UPDATE,DELETE')
  THEN
    RAISE EXCEPTION 'retention writer ACL boundary drifted';
  END IF;

  action_definition := pg_catalog.pg_get_functiondef(retention_action);
  policy_definition := pg_catalog.pg_get_functiondef(configure_policy);
  action_advisory_position := strpos(action_definition,
    'pg_advisory_xact_lock');
  action_replay_position := strpos(action_definition,
    'INTO replay_row');
  action_fence_position := strpos(action_definition,
    'acquire_personal_target_merge_generation_fence_v1');
  action_update_position := strpos(action_definition, 'FOR UPDATE');
  action_clock_position := strpos(
    substr(action_definition, action_update_position + 1),
    'event_time := clock_timestamp()'
  ) + action_update_position;
  action_fresh_auth_position := strpos(
    substr(action_definition, action_clock_position + 1),
    'IF NOT app_data.promotion_target_context_authorized'
  ) + action_clock_position;
  action_due_position := strpos(action_definition,
    'due_at := app_data.promotion_target_review_due_at');
  policy_auth_position := strpos(policy_definition,
    'IF NOT app_data.promotion_target_context_authorized');
  policy_fence_position := strpos(policy_definition,
    'acquire_personal_target_merge_generation_fence_v1');
  policy_fresh_auth_position := strpos(
    substr(policy_definition, policy_fence_position + 1),
    'IF NOT app_data.promotion_target_context_authorized'
  ) + policy_fence_position;
  policy_upsert_position := strpos(policy_definition,
    'INSERT INTO app_data.promotion_target_retention_policies');

  IF action_advisory_position = 0 OR action_replay_position = 0
    OR action_fence_position = 0 OR action_update_position = 0
    OR NOT (action_advisory_position < action_replay_position
      AND action_replay_position < action_fence_position
      AND action_fence_position < action_update_position)
    OR action_clock_position <= action_update_position
    OR action_fresh_auth_position <= action_clock_position
    OR action_due_position <= action_fresh_auth_position
  THEN
    RAISE EXCEPTION 'retention action replay/fence/row/timing order drifted';
  END IF;

  IF policy_auth_position = 0 OR policy_fence_position = 0
    OR policy_fresh_auth_position <= policy_fence_position
    OR policy_upsert_position <= policy_fresh_auth_position
  THEN
    RAISE EXCEPTION 'retention policy auth/fence/upsert order drifted';
  END IF;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0116_retention_merge_generation_fence') <> 1
  THEN
    RAISE EXCEPTION '0116 migration was not recorded once';
  END IF;
END
$check$;

SELECT 'retention merge-generation fence: passed' AS result;
