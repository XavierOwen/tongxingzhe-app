\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE public.fixture_0116_upgrade_catalog AS
SELECT
  procedure_row.oid AS function_oid,
  procedure_row.oid::regprocedure::text AS function_name,
  procedure_row.proowner AS function_owner,
  procedure_row.proacl AS function_acl,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS function_result
FROM pg_catalog.pg_proc AS procedure_row
WHERE procedure_row.oid IN (
  'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
  'app_data.configure_promotion_target_retention_policy(uuid,uuid,uuid,integer)'::regprocedure,
  'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure,
  'app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamp with time zone)'::regprocedure,
  'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'::regprocedure,
  'app_private.acquire_personal_target_merge_generation_fence_v1()'::regprocedure
);

GRANT SELECT ON public.fixture_0113_upgrade_context,
  public.fixture_0115_upgrade_state TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
DO $old_writers$
DECLARE
  configured_months integer;
BEGIN
  SELECT app_data.configure_promotion_target_retention_policy(
    context_row.app_user_id,
    context_row.workspace_id,
    context_row.project_id,
    9
  )
  INTO STRICT configured_months
  FROM public.fixture_0113_upgrade_context AS context_row;
  IF configured_months <> 9 THEN
    RAISE EXCEPTION '0115 retention policy baseline drift';
  END IF;

  PERFORM result
  FROM public.fixture_0113_upgrade_context AS context_row
  CROSS JOIN public.fixture_0115_upgrade_state AS saved
  CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
    context_row.app_user_id,
    context_row.workspace_id,
    context_row.project_id,
    saved.institution_target_id,
    'renew',
    'purpose_confirmed',
    '0116-upgrade-retention-renewal'
  );
END
$old_writers$;
RESET ROLE;

CREATE TABLE public.fixture_0116_upgrade_state AS
SELECT
  context_row.workspace_id,
  saved.institution_target_id,
  saved.relationship_id,
  to_jsonb(target_row) AS target_document,
  to_jsonb(relationship_row) AS relationship_document,
  (
    SELECT jsonb_agg(to_jsonb(revision_row)
      ORDER BY revision_row.revision_number)
    FROM app_data.promotion_target_institution_relation_revisions AS revision_row
    WHERE revision_row.relationship_id = saved.relationship_id
  ) AS revision_documents,
  (
    SELECT jsonb_agg(to_jsonb(event_row)
      ORDER BY event_row.occurred_at, event_row.event_id)
    FROM app_data.promotion_target_retention_events AS event_row
    WHERE event_row.promotion_target_id = saved.institution_target_id
  ) AS retention_documents,
  to_jsonb(policy_row) AS policy_document,
  app_data.promotion_target_review_due_at(saved.institution_target_id)
    AS current_review_due_at
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0115_upgrade_state AS saved
JOIN app_data.promotion_targets AS target_row
  ON target_row.promotion_target_id = saved.institution_target_id
JOIN app_data.promotion_target_institution_relationships AS relationship_row
  ON relationship_row.relationship_id = saved.relationship_id
JOIN app_data.promotion_target_retention_policies AS policy_row
  ON policy_row.workspace_id = context_row.workspace_id;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0116_upgrade_catalog) <> 6
    OR (SELECT count(*) FROM public.fixture_0116_upgrade_state) <> 1
    OR (SELECT jsonb_array_length(revision_documents)
        FROM public.fixture_0116_upgrade_state) <> 1
    OR (SELECT jsonb_array_length(retention_documents)
        FROM public.fixture_0116_upgrade_state) <> 2
    OR NOT EXISTS (
      SELECT 1
      FROM public.fixture_0116_upgrade_state
      WHERE policy_document->>'retention_months' = '9'
        AND current_review_due_at IS NOT NULL
    )
  THEN
    RAISE EXCEPTION '0115 retention generation fence upgrade baseline drift';
  END IF;
END
$baseline$;

COMMIT;
