\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0156_management_follow_up_consent_opt_in_read_isolation'
  THEN RAISE EXCEPTION 'duplicate whitespace upgrade requires the real 0156 baseline'; END IF;
END
$baseline$;

CREATE TABLE public.fixture_0156_duplicate_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0156-duplicate.example.test','owner');
SELECT * FROM app_data.list_personal_project_contexts('https://0156-duplicate.example.test','owner');
SELECT created.* FROM public.fixture_0156_duplicate_context context
CROSS JOIN LATERAL app_data.create_promotion_target(
  context.app_user_id,context.workspace_id,context.project_id,'person','Existing padded value',
  E'\t+1-555-0156\t',E'\tCase0156@example.test\t','0156-duplicate-existing'
) created;

CREATE TABLE public.fixture_0156_duplicate_rows AS
SELECT 'completed'::text AS kind,jsonb_build_array(jsonb_build_object(
  'target_type','person','display_name','Completed legacy import',
  'phone',E'\t+1-555-9960\t','email',E'\tLegacy@example.test\t'
)) AS rows
UNION ALL
SELECT 'pending',jsonb_build_array(jsonb_build_object(
  'target_type','person','display_name','Pending matching import',
  'phone','+1-555-0156','email',NULL
));
CREATE TABLE public.fixture_0156_duplicate_previews AS
SELECT rows.kind,preview.*
FROM public.fixture_0156_duplicate_context context
CROSS JOIN public.fixture_0156_duplicate_rows rows
CROSS JOIN LATERAL app_data.preview_personal_target_csv_import_v1(
  'https://0156-duplicate.example.test','owner',context.project_id,rows.rows
) preview;
CREATE TABLE public.fixture_0156_duplicate_completed AS
SELECT confirmation.*
FROM public.fixture_0156_duplicate_context context
JOIN public.fixture_0156_duplicate_previews preview ON preview.kind='completed'
JOIN public.fixture_0156_duplicate_rows rows ON rows.kind=preview.kind
CROSS JOIN LATERAL app_data.confirm_personal_target_csv_import_v1(
  'https://0156-duplicate.example.test','owner',context.project_id,
  preview.preview_id,'00000000-0156-4000-8000-000000009960',rows.rows,'["create"]'
) confirmation;
DO $receipts$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0156_duplicate_previews WHERE hinted_rows=ARRAY[]::integer[])<>2
    OR NOT EXISTS (SELECT 1 FROM public.fixture_0156_duplicate_completed
      WHERE outcome='confirmed' AND created_count=1)
  THEN RAISE EXCEPTION '0156 baseline did not preserve its raw import and pending preview'; END IF;
END
$receipts$;

CREATE TEMP TABLE fixture_0156_plain_pair ON COMMIT DROP AS
SELECT created.target FROM public.fixture_0156_duplicate_context context
CROSS JOIN (VALUES ('first'),('second')) name(value)
CROSS JOIN LATERAL app_data.create_promotion_target(
  context.app_user_id,context.workspace_id,context.project_id,'person','Plain pair '||name.value,
  '+1-555-0156-plain',NULL,'0156-plain-pair-'||name.value
) created;
CREATE TEMP TABLE fixture_0156_pair_preview ON COMMIT DROP AS
SELECT preview.* FROM public.fixture_0156_duplicate_context context
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0156-duplicate.example.test','owner',context.project_id,
  (SELECT min((target->>'target_id')::text)::uuid FROM fixture_0156_plain_pair),
  (SELECT max((target->>'target_id')::text)::uuid FROM fixture_0156_plain_pair)
) preview;
CREATE TABLE public.fixture_0156_duplicate_pair_receipt AS
SELECT receipt.* FROM app_private.personal_target_pair_preview_receipts receipt
JOIN fixture_0156_pair_preview preview USING(preview_id);
CREATE TABLE public.fixture_0156_duplicate_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0156_duplicate_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0156_duplicate_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  frozen public.fixture_0156_duplicate_snapshot%ROWTYPE;
  context public.fixture_0156_duplicate_context%ROWTYPE;
  preview public.fixture_0156_duplicate_previews%ROWTYPE;
  rows jsonb;
  result jsonb;
BEGIN
  SELECT * INTO STRICT frozen FROM public.fixture_0156_duplicate_snapshot;
  SELECT * INTO STRICT context FROM public.fixture_0156_duplicate_context;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>frozen.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM frozen.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0156_duplicate_catalog old
      FULL JOIN (
        SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
        WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
          AND oid<>'app_private.personal_target_duplicate_contact_signal_v1(text)'::regprocedure
      ) live USING(oid)
      WHERE CASE WHEN oid IN (
        'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure,
        'app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamptz)'::regprocedure,
        'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure
      ) THEN (old.catalog_row-'prosrc') IS DISTINCT FROM (live.catalog_row-'prosrc')
        ELSE old.catalog_row IS DISTINCT FROM live.catalog_row END
    )
  THEN RAISE EXCEPTION '0156→0157 changed old rows or function metadata beyond duplicate comparisons'; END IF;

  SELECT * INTO STRICT preview FROM public.fixture_0156_duplicate_previews WHERE kind='completed';
  SELECT source.rows INTO STRICT rows FROM public.fixture_0156_duplicate_rows source WHERE kind='completed';
  SELECT to_jsonb(confirmation) INTO STRICT result
  FROM app_data.confirm_personal_target_csv_import_v1(
    'https://0156-duplicate.example.test','owner',context.project_id,preview.preview_id,
    '00000000-0156-4000-8000-000000009960',rows,'["create"]'
  ) confirmation;
  IF result IS DISTINCT FROM (SELECT to_jsonb(saved) FROM public.fixture_0156_duplicate_completed saved)
    OR (SELECT to_jsonb(receipt) FROM app_private.validate_personal_target_pair_preview_v1(
      context.app_user_id,context.project_id,
      (SELECT preview_id FROM public.fixture_0156_duplicate_pair_receipt),clock_timestamp()
    ) receipt) IS DISTINCT FROM (SELECT to_jsonb(saved) FROM public.fixture_0156_duplicate_pair_receipt saved)
    OR pg_temp.fixture_database_state() IS DISTINCT FROM frozen.business_state
  THEN RAISE EXCEPTION '0157 changed a completed raw CSV import, pair receipt, or replay state'; END IF;

  SELECT * INTO STRICT preview FROM public.fixture_0156_duplicate_previews WHERE kind='pending';
  SELECT source.rows INTO STRICT rows FROM public.fixture_0156_duplicate_rows source WHERE kind='pending';
  SELECT to_jsonb(confirmation) INTO STRICT result
  FROM app_data.confirm_personal_target_csv_import_v1(
    'https://0156-duplicate.example.test','owner',context.project_id,preview.preview_id,
    gen_random_uuid(),rows,'["create"]'
  ) confirmation;
  IF result->>'outcome' IS DISTINCT FROM 'stale_preview'
    OR (result->>'created_count')::integer IS DISTINCT FROM 0
    OR (SELECT jsonb_agg(to_jsonb(target) ORDER BY to_jsonb(target)::text)
      FROM app_data.promotion_targets target) IS DISTINCT FROM frozen.business_state->'app_data.promotion_targets'
  THEN RAISE EXCEPTION '0157 allowed an old no-hint preview to create a matching target'; END IF;
END
$function$;
