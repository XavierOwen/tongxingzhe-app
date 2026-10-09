\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE public.fixture_0113_upgrade_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0113-upgrade.example.test',
  'owner'
);

INSERT INTO app_data.user_current_projects (app_user_id, project_id)
SELECT app_user_id, project_id
FROM public.fixture_0113_upgrade_context;

CREATE TABLE public.fixture_0113_upgrade_catalog AS
SELECT
  procedure_row.oid AS function_oid,
  procedure_row.oid::regprocedure::text AS function_name,
  procedure_row.proowner AS function_owner,
  procedure_row.proacl AS function_acl,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS function_result
FROM pg_catalog.pg_proc AS procedure_row
WHERE procedure_row.oid IN (
  'app_data.list_personal_project_contexts(text,text)'::regprocedure,
  'app_data.preview_personal_target_csv_import_v1(text,text,uuid,jsonb)'::regprocedure,
  'app_data.confirm_personal_target_csv_import_v1(text,text,uuid,uuid,uuid,jsonb,jsonb)'::regprocedure,
  'app_data.prepare_personal_target_pii_export_v1(text,text,uuid,timestamptz)'::regprocedure
);

CREATE TABLE public.fixture_0113_upgrade_capabilities AS
SELECT capabilities
FROM app_data.list_personal_project_contexts(
  'https://synthetic-0113-upgrade.example.test',
  'owner'
)
WHERE is_current;

CREATE TABLE public.fixture_0113_upgrade_import_rows (
  rows jsonb PRIMARY KEY
);
INSERT INTO public.fixture_0113_upgrade_import_rows (rows)
VALUES (jsonb_build_array(jsonb_build_object(
  'target_type', 'person',
  'display_name', '0112 baseline imported target',
  'phone', '+1 312 555 0113',
  'email', 'upgrade-0113@example.test'
)));

CREATE TABLE public.fixture_0113_upgrade_preview AS
SELECT preview.*
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0113_upgrade_import_rows AS input_row
CROSS JOIN LATERAL app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0113-upgrade.example.test',
  'owner',
  context_row.project_id,
  input_row.rows
) AS preview;

CREATE TABLE public.fixture_0113_upgrade_confirm AS
SELECT confirmed.*
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0113_upgrade_import_rows AS input_row
CROSS JOIN public.fixture_0113_upgrade_preview AS preview_row
CROSS JOIN LATERAL app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0113-upgrade.example.test',
  'owner',
  context_row.project_id,
  preview_row.preview_id,
  '00000000-0113-4000-8000-000000000001'::uuid,
  input_row.rows,
  '["create"]'::jsonb
) AS confirmed;

CREATE TABLE public.fixture_0113_upgrade_export AS
SELECT
  exported.export_bytes,
  convert_from(exported.export_bytes, 'UTF8')::jsonb AS export_document
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN LATERAL (
  SELECT app_data.prepare_personal_target_pii_export_v1(
    'https://synthetic-0113-upgrade.example.test',
    'owner',
    context_row.project_id,
    clock_timestamp() - interval '1 minute'
  ) AS export_bytes
) AS exported;

CREATE TABLE public.fixture_0113_upgrade_state AS
SELECT
  target_row.promotion_target_id,
  to_jsonb(target_row) AS target_document,
  (
    SELECT jsonb_agg(to_jsonb(assignment_row)
      ORDER BY assignment_row.assignment_id)
    FROM app_data.promotion_target_assignments AS assignment_row
    WHERE assignment_row.promotion_target_id = target_row.promotion_target_id
  ) AS assignment_documents,
  (SELECT count(*) FROM app_private.personal_target_csv_import_previews)
    AS import_preview_count,
  (SELECT count(*) FROM app_private.personal_target_csv_import_request_claims)
    AS import_claim_count,
  (SELECT count(*) FROM app_private.personal_target_csv_import_audit_events)
    AS import_audit_count,
  (SELECT count(*) FROM app_private.personal_target_pii_export_events)
    AS export_audit_count
FROM public.fixture_0113_upgrade_confirm AS confirmed
JOIN app_data.promotion_targets AS target_row
  ON target_row.promotion_target_id =
    (confirmed.created_targets->0->>'target_id')::uuid;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0113_upgrade_context) <> 1
    OR (SELECT count(*) FROM public.fixture_0113_upgrade_catalog) <> 4
    OR (SELECT count(*) FROM public.fixture_0113_upgrade_capabilities) <> 1
    OR NOT EXISTS (
      SELECT 1 FROM public.fixture_0113_upgrade_capabilities
      WHERE 'import_target_pii' = ANY(capabilities)
        AND 'export_target_pii' = ANY(capabilities)
        AND NOT 'manage_assigned_target_merges' = ANY(capabilities)
    )
    OR NOT EXISTS (
      SELECT 1 FROM public.fixture_0113_upgrade_confirm
      WHERE outcome = 'confirmed'
        AND row_count = 1
        AND created_count = 1
        AND jsonb_array_length(created_targets) = 1
    )
    OR NOT EXISTS (
      SELECT 1 FROM public.fixture_0113_upgrade_export
      WHERE export_document->>'export_contract_id' =
          'personal_promotion_target_pii_export_v1'
        AND jsonb_array_length(export_document->'targets') = 1
        AND export_document->'targets'->0->>'display_name' =
          '0112 baseline imported target'
    )
    OR (SELECT count(*) FROM public.fixture_0113_upgrade_state) <> 1
  THEN
    RAISE EXCEPTION '0112 personal target pair upgrade baseline drift';
  END IF;
END
$baseline$;

COMMIT;
