\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE public.fixture_0117_upgrade_catalog AS
SELECT procedure_row.oid AS function_oid,
       procedure_row.oid::regprocedure::text AS function_name,
       procedure_row.proowner AS function_owner,
       procedure_row.proacl AS function_acl,
       procedure_row.prosecdef AS security_definer,
       procedure_row.provolatile AS volatility,
       procedure_row.proconfig AS function_config,
       pg_catalog.pg_get_function_result(procedure_row.oid) AS function_result
FROM pg_catalog.pg_proc AS procedure_row
WHERE procedure_row.oid IN (
  'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
  'app_data.configure_promotion_target_retention_policy(uuid,uuid,uuid,integer)'::regprocedure,
  'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure,
  'app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamp with time zone)'::regprocedure,
  'app_private.cleanup_personal_target_pair_preview_receipts_v1()'::regprocedure,
  'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'::regprocedure,
  'app_private.acquire_personal_target_merge_generation_fence_v1()'::regprocedure
);

CREATE TABLE public.fixture_0117_upgrade_state AS
SELECT
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
  (SELECT max(version) FROM app_migrations.schema_migrations) AS latest_migration,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.preview_id)
   FROM app_private.personal_target_pair_preview_receipts AS row_value)
    AS preview_receipts,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.generation_id)
   FROM app_private.personal_target_merge_generations_v1 AS row_value)
    AS generations,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.generation_id, row_value.promotion_target_id)
   FROM app_private.personal_target_merge_generation_members_v1 AS row_value)
    AS generation_members,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.promotion_target_id)
   FROM app_private.personal_target_merge_active_members_v1 AS row_value)
    AS active_members,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.promotion_target_id)
   FROM app_data.promotion_targets AS row_value)
    AS targets,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.contact_id, row_value.revision_number,
        row_value.promotion_target_id)
   FROM app_data.contact_target_links AS row_value)
    AS contact_links,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.promotion_target_id, row_value.project_id)
   FROM app_data.promotion_target_project_relationships AS row_value)
    AS project_relationships,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.promotion_target_id, row_value.project_id,
        row_value.revision_number)
   FROM app_data.promotion_target_relationship_revisions AS row_value)
    AS project_relationship_revisions,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.promotion_target_id, row_value.event_id)
   FROM app_data.promotion_target_retention_events AS row_value)
    AS retention_events,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.workspace_id)
   FROM app_data.promotion_target_retention_policies AS row_value)
    AS retention_policies;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0117_upgrade_catalog) <> 7
    OR (SELECT count(*) FROM public.fixture_0117_upgrade_state) <> 1
    OR (SELECT migration_count FROM public.fixture_0117_upgrade_state) <> 115
    OR (SELECT latest_migration FROM public.fixture_0117_upgrade_state)
      IS DISTINCT FROM '0116_retention_merge_generation_fence'
  THEN
    RAISE EXCEPTION '0116→0117 live upgrade baseline drift';
  END IF;
END
$baseline$;

COMMIT;
