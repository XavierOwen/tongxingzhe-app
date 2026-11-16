\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0157_personal_target_duplicate_contact_whitespace'
  THEN RAISE EXCEPTION 'CSV normalization upgrade requires the real 0157 baseline'; END IF;
END
$baseline$;

CREATE TABLE public.fixture_0157_csv_whitespace_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0157-csv-whitespace.example.test','owner');
SELECT * FROM app_data.list_personal_project_contexts('https://0157-csv-whitespace.example.test','owner');
CREATE TABLE public.fixture_0157_csv_whitespace_inputs AS
SELECT kind,gen_random_uuid() AS request_id,jsonb_build_array(jsonb_build_object(
  'target_type','person','display_name',display_name,'phone',phone,'email',email
)) AS rows FROM (VALUES
  ('completed_plain','Completed plain CSV','+1-555-0157-plain',NULL::text),
  ('completed_raw','Completed raw CSV',E'\t',U&'\00A0'),
  ('pending_optional','Pending optional CSV',E'\t',U&'\00A0'),
  ('pending_name',E'\t',NULL,NULL),
  ('pending_plain','Pending plain CSV','+1-555-0157-pending','pending0157@example.test')
) input(kind,display_name,phone,email);
CREATE TABLE public.fixture_0157_csv_whitespace_previews AS
SELECT input.kind,preview.* FROM public.fixture_0157_csv_whitespace_context context
CROSS JOIN public.fixture_0157_csv_whitespace_inputs input
CROSS JOIN LATERAL app_data.preview_personal_target_csv_import_v1(
  'https://0157-csv-whitespace.example.test','owner',context.project_id,input.rows
) preview;
CREATE TABLE public.fixture_0157_csv_whitespace_completed AS
SELECT input.kind,confirmation.* FROM public.fixture_0157_csv_whitespace_context context
CROSS JOIN public.fixture_0157_csv_whitespace_inputs input
JOIN public.fixture_0157_csv_whitespace_previews preview USING(kind)
CROSS JOIN LATERAL app_data.confirm_personal_target_csv_import_v1(
  'https://0157-csv-whitespace.example.test','owner',context.project_id,
  preview.preview_id,input.request_id,input.rows,'["create"]'
) confirmation WHERE input.kind IN ('completed_plain','completed_raw');
DO $receipts$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0157_csv_whitespace_previews
      WHERE hinted_rows=ARRAY[]::integer[])<>5
    OR (SELECT count(*) FROM public.fixture_0157_csv_whitespace_completed
      WHERE outcome='confirmed' AND created_count=1)<>2
    OR NOT EXISTS (
      SELECT 1 FROM public.fixture_0157_csv_whitespace_completed result
      JOIN app_data.promotion_targets target
        ON target.promotion_target_id=(result.created_targets->0->>'target_id')::uuid
      WHERE result.kind='completed_raw' AND target.phone=E'\t' AND target.email=U&'\00A0'
    )
  THEN RAISE EXCEPTION '0157 did not preserve its raw completed import and pending previews'; END IF;
END
$receipts$;
CREATE TABLE public.fixture_0157_csv_whitespace_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0157_csv_whitespace_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

-- Pending confirmations write only inside the caller's BEGIN/ROLLBACK assertion transaction.
CREATE FUNCTION public.fixture_0157_csv_whitespace_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  frozen public.fixture_0157_csv_whitespace_snapshot%ROWTYPE;
  context public.fixture_0157_csv_whitespace_context%ROWTYPE;
  input record;
  current_state jsonb;
  before_replay jsonb;
  result jsonb;
  target_id uuid;
  rejected boolean:=false;
BEGIN
  SELECT * INTO STRICT frozen FROM public.fixture_0157_csv_whitespace_snapshot;
  SELECT * INTO STRICT context FROM public.fixture_0157_csv_whitespace_context;
  current_state:=pg_temp.fixture_database_state();
  current_state:=jsonb_set(current_state,'{app_private.personal_target_csv_import_previews}',
    (SELECT coalesce(jsonb_agg(value-'normalization_version' ORDER BY (value-'normalization_version')::text),'[]'::jsonb)
      FROM jsonb_array_elements(current_state->'app_private.personal_target_csv_import_previews')));
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>frozen.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0158_personal_target_csv_import_whitespace'
    OR current_state IS DISTINCT FROM frozen.business_state
    OR EXISTS (SELECT 1 FROM app_private.personal_target_csv_import_previews WHERE normalization_version<>1)
    OR EXISTS (
      SELECT 1 FROM public.fixture_0157_csv_whitespace_catalog old
      FULL JOIN (
        SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
        WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
          AND oid<>'app_private.canonical_personal_target_csv_import_rows_v2(jsonb)'::regprocedure
      ) live USING(oid)
      WHERE CASE WHEN oid IN (
        'app_data.preview_personal_target_csv_import_v1(text,text,uuid,jsonb)'::regprocedure,
        'app_data.confirm_personal_target_csv_import_v1(text,text,uuid,uuid,uuid,jsonb,jsonb)'::regprocedure
      ) THEN (old.catalog_row-'prosrc') IS DISTINCT FROM (live.catalog_row-'prosrc')
        ELSE old.catalog_row IS DISTINCT FROM live.catalog_row END
    )
  THEN RAISE EXCEPTION '0157→0158 changed old rows or catalog beyond versioned CSV normalization'; END IF;

  before_replay:=pg_temp.fixture_database_state();
  FOR input IN SELECT source.*,preview.preview_id
    FROM public.fixture_0157_csv_whitespace_inputs source
    JOIN public.fixture_0157_csv_whitespace_previews preview USING(kind)
    WHERE source.kind IN ('completed_plain','completed_raw')
  LOOP
    SELECT to_jsonb(confirmation) INTO STRICT result
    FROM app_data.confirm_personal_target_csv_import_v1(
      'https://0157-csv-whitespace.example.test','owner',context.project_id,
      input.preview_id,input.request_id,input.rows,'["create"]'
    ) confirmation;
    IF result IS DISTINCT FROM (SELECT to_jsonb(saved)-'kind'
      FROM public.fixture_0157_csv_whitespace_completed saved WHERE saved.kind=input.kind)
    THEN RAISE EXCEPTION '0158 changed completed legacy CSV replay: %',input.kind; END IF;
  END LOOP;
  SELECT source.*,preview.preview_id INTO STRICT input
  FROM public.fixture_0157_csv_whitespace_inputs source
  JOIN public.fixture_0157_csv_whitespace_previews preview USING(kind)
  WHERE source.kind='completed_plain';
  BEGIN
    PERFORM 1 FROM app_data.confirm_personal_target_csv_import_v1(
      'https://0157-csv-whitespace.example.test','owner',context.project_id,
      input.preview_id,input.request_id,jsonb_set(input.rows,'{0,phone}',
        to_jsonb(E'\t+1-555-0157-plain\t'::text)),'["create"]'
    );
  EXCEPTION WHEN SQLSTATE '23505' THEN rejected:=true;
  END;
  IF NOT rejected OR pg_temp.fixture_database_state() IS DISTINCT FROM before_replay
  THEN RAISE EXCEPTION '0158 allowed v2 fallback or changed legacy replay state'; END IF;

  FOR input IN SELECT source.*,preview.preview_id
    FROM public.fixture_0157_csv_whitespace_inputs source
    JOIN public.fixture_0157_csv_whitespace_previews preview USING(kind)
    WHERE source.kind IN ('pending_optional','pending_name')
  LOOP
    SELECT to_jsonb(confirmation) INTO STRICT result
    FROM app_data.confirm_personal_target_csv_import_v1(
      'https://0157-csv-whitespace.example.test','owner',context.project_id,
      input.preview_id,input.request_id,input.rows,'["create"]'
    ) confirmation;
    IF result->>'outcome' IS DISTINCT FROM 'stale_preview'
      OR (result->>'created_count')::integer IS DISTINCT FROM 0
      OR (SELECT coalesce(jsonb_agg(to_jsonb(target) ORDER BY to_jsonb(target)::text),'[]'::jsonb)
        FROM app_data.promotion_targets target) IS DISTINCT FROM frozen.business_state->'app_data.promotion_targets'
    THEN RAISE EXCEPTION '0158 created values from changed legacy CSV preview: %',input.kind; END IF;
  END LOOP;
  SELECT source.*,preview.preview_id INTO STRICT input
  FROM public.fixture_0157_csv_whitespace_inputs source
  JOIN public.fixture_0157_csv_whitespace_previews preview USING(kind)
  WHERE source.kind='pending_plain';
  SELECT to_jsonb(confirmation) INTO STRICT result
  FROM app_data.confirm_personal_target_csv_import_v1(
    'https://0157-csv-whitespace.example.test','owner',context.project_id,
    input.preview_id,input.request_id,input.rows,'["create"]'
  ) confirmation;
  target_id:=(result->'created_targets'->0->>'target_id')::uuid;
  IF result->>'outcome' IS DISTINCT FROM 'confirmed'
    OR (result->>'created_count')::integer IS DISTINCT FROM 1
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_targets target
      WHERE target.promotion_target_id=target_id AND target.display_name='Pending plain CSV'
        AND target.phone='+1-555-0157-pending' AND target.email='pending0157@example.test')
    OR (SELECT coalesce(jsonb_agg(to_jsonb(target) ORDER BY to_jsonb(target)::text),'[]'::jsonb)
      FROM app_data.promotion_targets target WHERE target.promotion_target_id<>target_id)
      IS DISTINCT FROM frozen.business_state->'app_data.promotion_targets'
  THEN RAISE EXCEPTION '0158 changed an unchanged legacy pending CSV confirmation or old targets'; END IF;
END
$function$;
