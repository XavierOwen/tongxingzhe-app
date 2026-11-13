\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  runtime_role oid := 'tongxingzhe_runtime'::regrole;
  calculation record;
  function_row pg_proc%ROWTYPE;
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  FOR calculation IN
    SELECT * FROM (VALUES
      (
        'app_data.promotion_target_review_due_at(uuid)', 's', 'sql', false,
        $expression$pg_catalog.date_add(app_data.promotion_target_retention_reference_at(
      target_row.promotion_target_id
    ), make_interval(months => COALESCE(
      policy_row.retention_months,
      12
    )), 'UTC')$expression$,
        ') + make_interval(months'
      ),
      (
        'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)', 'v', 'plpgsql', true,
        $expression$pg_catalog.date_add(GREATEST(event_time,
        app_data.promotion_target_retention_reference_at(requested_target_id)
      ), make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12)), 'UTC')$expression$,
        'event_time + make_interval(months'
      ),
      (
        'app_data.list_promotion_target_retention_tasks(uuid,uuid,uuid)', 'v', 'plpgsql', true,
        $expression$clock_timestamp() + interval '720 hours'$expression$,
        $old$clock_timestamp() + interval '30 days'$old$
      )
    ) AS calculations(signature, volatility, language_name, runtime_execute, expression, old_expression)
  LOOP
    SELECT * INTO STRICT function_row FROM pg_catalog.pg_proc
    WHERE oid = calculation.signature::regprocedure;
    IF function_row.proowner <> trusted_owner OR NOT function_row.prosecdef
      OR function_row.provolatile::text <> calculation.volatility
      OR function_row.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, app_data']::text[]
      OR function_row.prolang <> (SELECT oid FROM pg_catalog.pg_language
        WHERE lanname = calculation.language_name)
    THEN
      RAISE EXCEPTION 'retention calendar function metadata drifted: %', calculation.signature;
    END IF;
    IF has_function_privilege(runtime_role, function_row.oid, 'EXECUTE') <> calculation.runtime_execute
      OR EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
          function_row.proacl, pg_catalog.acldefault('f', function_row.proowner)
        )) acl
        WHERE acl.grantee <> function_row.proowner
          AND (NOT calculation.runtime_execute OR acl.grantee <> runtime_role)
      )
    THEN
      RAISE EXCEPTION 'retention calendar function ACL drifted: %', calculation.signature;
    END IF;
    IF length(function_row.prosrc) - length(replace(function_row.prosrc, calculation.expression, ''))
        <> length(calculation.expression)
      OR position(calculation.old_expression IN function_row.prosrc) <> 0
    THEN
      RAISE EXCEPTION 'retention calendar must calculate explicitly in UTC: %', calculation.signature;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0153_promotion_target_retention_calendar') <> 1 THEN
    RAISE EXCEPTION '0153 retention calendar migration was not recorded once';
  END IF;
END
$check$;

SELECT 'promotion target retention UTC calendar: passed' AS result;
