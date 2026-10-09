\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE public.fixture_0115_upgrade_catalog AS
SELECT procedure_row.oid AS function_oid,
       procedure_row.oid::regprocedure::text AS function_name,
       procedure_row.proowner AS function_owner,
       procedure_row.proacl AS function_acl,
       pg_catalog.pg_get_function_result(procedure_row.oid) AS function_result
FROM pg_catalog.pg_proc AS procedure_row
WHERE procedure_row.oid IN (
  'app_data.create_target_institution_relationship(uuid,uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
  'app_data.end_target_institution_relationship(uuid,uuid,uuid,uuid,integer,text)'::regprocedure,
  'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)'::regprocedure,
  'app_data.update_promotion_target_relationship(uuid,uuid,uuid,uuid,integer,integer,text,text,text,text,text,uuid)'::regprocedure,
  'app_private.bind_personal_target_merge_generation_v1()'::regprocedure,
  'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamp with time zone)'::regprocedure,
  'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure,
  'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'::regprocedure,
  'app_data.confirm_personal_target_csv_import_v1(text,text,uuid,uuid,uuid,jsonb,jsonb)'::regprocedure,
  'app_data.prepare_personal_target_pii_export_v1(text,text,uuid,timestamp with time zone)'::regprocedure
);

GRANT SELECT ON public.fixture_0113_upgrade_context,
  public.fixture_0113_upgrade_state TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0115_upgrade_institution AS
SELECT created.target
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN LATERAL app_data.create_promotion_target(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id,
  'institution', '0114 preexisting institution relation', NULL, NULL,
  '0115-upgrade-institution'
) AS created;
CREATE TEMP TABLE fixture_0115_upgrade_relationship AS
SELECT result FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0113_upgrade_state AS person_row
CROSS JOIN fixture_0115_upgrade_institution AS institution_row
CROSS JOIN LATERAL app_data.create_target_institution_relationship(
  context_row.app_user_id,
  context_row.workspace_id,
  context_row.project_id,
  person_row.promotion_target_id,
  (institution_row.target->>'target_id')::uuid,
  'membership_affiliation', 'preexisting relationship',
  '0115-upgrade-relation-create'
);
CREATE TEMP TABLE fixture_0115_upgrade_retention AS
SELECT result FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN fixture_0115_upgrade_institution AS institution_row
CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  context_row.app_user_id,
  context_row.workspace_id,
  context_row.project_id,
  (institution_row.target->>'target_id')::uuid,
  'renew', 'purpose_confirmed', '0115-upgrade-retention-renewal'
);
RESET ROLE;

CREATE TABLE public.fixture_0115_upgrade_state AS
SELECT
  (institution_row.target->>'target_id')::uuid AS institution_target_id,
  (relationship_row.result->'relationship'->>'relationship_id')::uuid
    AS relationship_id,
  (
    SELECT to_jsonb(saved) - 'person_merge_generation_id'
      - 'institution_merge_generation_id'
    FROM app_data.promotion_target_institution_relationships AS saved
    WHERE saved.relationship_id =
      (relationship_row.result->'relationship'->>'relationship_id')::uuid
  ) AS relationship_document,
  (
    SELECT jsonb_agg(to_jsonb(saved)
      ORDER BY saved.revision_number)
    FROM app_data.promotion_target_institution_relation_revisions AS saved
    WHERE saved.relationship_id =
      (relationship_row.result->'relationship'->>'relationship_id')::uuid
  ) AS revision_documents,
  (
    SELECT jsonb_agg(to_jsonb(event_row)
      ORDER BY event_row.occurred_at, event_row.event_id)
    FROM app_data.promotion_target_retention_events AS event_row
    WHERE event_row.promotion_target_id =
      (institution_row.target->>'target_id')::uuid
  ) AS retention_documents
FROM fixture_0115_upgrade_institution AS institution_row
CROSS JOIN fixture_0115_upgrade_relationship AS relationship_row;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0115_upgrade_catalog) <> 10
    OR (SELECT count(*) FROM public.fixture_0115_upgrade_state) <> 1
    OR (SELECT jsonb_array_length(revision_documents)
        FROM public.fixture_0115_upgrade_state) <> 1
    OR (SELECT jsonb_array_length(retention_documents)
        FROM public.fixture_0115_upgrade_state) <> 1
  THEN
    RAISE EXCEPTION '0114 institution relationship upgrade baseline drift';
  END IF;
END
$baseline$;

COMMIT;
