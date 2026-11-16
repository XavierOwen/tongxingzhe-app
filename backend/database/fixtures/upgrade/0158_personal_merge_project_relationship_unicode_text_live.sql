\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0158_personal_target_csv_import_whitespace'
  THEN RAISE EXCEPTION 'pending Unicode text upgrade requires the real 0158 baseline'; END IF;
END
$baseline$;
CREATE TABLE public.fixture_0158_unicode_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0158-pending-unicode.example.test','owner');
SELECT * FROM app_data.list_personal_project_contexts('https://0158-pending-unicode.example.test','owner');
CREATE TEMP TABLE fixture_0158_unicode_targets ON COMMIT DROP AS
SELECT name.value AS name,created.target
FROM public.fixture_0158_unicode_context context CROSS JOIN (VALUES('first'),('second')) name(value)
CROSS JOIN LATERAL app_data.create_promotion_target(
  context.app_user_id,context.workspace_id,context.project_id,'person','Unicode seed '||name.value,
  '+1-555-0159-upgrade',NULL,'0158-unicode-'||name.value
) created;
CREATE TEMP TABLE fixture_0158_unicode_preview ON COMMIT DROP AS
SELECT preview.* FROM public.fixture_0158_unicode_context context
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0158-pending-unicode.example.test','owner',context.project_id,
  (SELECT (target->>'target_id')::uuid FROM fixture_0158_unicode_targets WHERE name='first'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0158_unicode_targets WHERE name='second')
) preview;
CREATE TABLE public.fixture_0158_unicode_generation AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  context.app_user_id,context.project_id,gen_random_uuid(),preview.preview_id,
  (SELECT (target->>'target_id')::uuid FROM fixture_0158_unicode_targets WHERE name='first'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0158_unicode_targets WHERE name='first'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0158_unicode_targets WHERE name='second'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0158_unicode_targets WHERE name='first')
) AS generation_id FROM public.fixture_0158_unicode_context context CROSS JOIN fixture_0158_unicode_preview preview;
CREATE TABLE public.fixture_0158_unicode_inputs AS
SELECT value.*,gen_random_uuid() AS request_id FROM (VALUES
  ('blank_both',U&'\202F',U&'\00A0'),
  ('blank_note',U&'\00A0','Original explanation'),
  ('blank_detail','Original note',U&'\202F'),
  ('meaningful',U&'\00A0Original note\00A0',U&'\FEFFOriginal explanation\FEFF')
) value(kind,note,detail);
CREATE TABLE public.fixture_0158_unicode_receipts AS
SELECT input.kind,to_jsonb(receipt) AS result
FROM public.fixture_0158_unicode_context context CROSS JOIN public.fixture_0158_unicode_generation generation
CROSS JOIN public.fixture_0158_unicode_inputs input
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(
  context.app_user_id,context.workspace_id,context.project_id,input.request_id,generation.generation_id,
  2,'active',input.note,'other',input.detail
) receipt;
DO $seed$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0158_unicode_receipts)<>4
    OR (SELECT count(*) FROM public.fixture_0158_unicode_receipts receipt
      JOIN public.fixture_0158_unicode_inputs input USING(kind)
      JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 payload
        ON payload.pending_fact_id=(receipt.result->>'pending_fact_id')::uuid
      WHERE payload.follow_up_note=input.note AND payload.reason_detail=input.detail)<>4
  THEN RAISE EXCEPTION '0158 did not seed the original Unicode payloads through the ordinary private writer'; END IF;
END
$seed$;
CREATE TABLE public.fixture_0158_unicode_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0158_unicode_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0158_unicode_text_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  frozen public.fixture_0158_unicode_snapshot%ROWTYPE;
  context public.fixture_0158_unicode_context%ROWTYPE;
  generation uuid;
  input record;
  result jsonb;
  before_error jsonb;
  actual_state text;
  actual_message text;
BEGIN
  SELECT * INTO STRICT frozen FROM public.fixture_0158_unicode_snapshot;
  SELECT * INTO STRICT context FROM public.fixture_0158_unicode_context;
  SELECT generation_id INTO STRICT generation FROM public.fixture_0158_unicode_generation;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>frozen.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM frozen.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0158_unicode_catalog old
      FULL JOIN (SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
        WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)) live USING(oid)
      WHERE CASE WHEN oid=
        'app_private.stage_unassigned_personal_merge_project_relationship_v1(uuid,uuid,uuid,uuid,uuid,integer,text,text,text,text)'::regprocedure
        THEN (old.catalog_row-'prosrc') IS DISTINCT FROM (live.catalog_row-'prosrc')
        ELSE old.catalog_row IS DISTINCT FROM live.catalog_row END
    )
  THEN RAISE EXCEPTION '0158→0159 changed old rows or function catalog beyond the stage guard'; END IF;
  FOR input IN SELECT source.*,receipt.result FROM public.fixture_0158_unicode_inputs source
    JOIN public.fixture_0158_unicode_receipts receipt USING(kind)
  LOOP
    SELECT to_jsonb(receipt) INTO STRICT result
    FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
      context.app_user_id,context.workspace_id,context.project_id,input.request_id,generation,
      2,'active',input.note,'other',input.detail
    ) receipt;
    IF result IS DISTINCT FROM input.result THEN
      RAISE EXCEPTION '0159 changed an original Unicode stage receipt: %',input.kind;
    END IF;
  END LOOP;
  -- Successful stage replay retains the original fence epoch advance.
  IF pg_temp.fixture_database_state()-'app_private.personal_target_merge_generation_fence_v1'
    IS DISTINCT FROM frozen.business_state-'app_private.personal_target_merge_generation_fence_v1'
  THEN RAISE EXCEPTION '0159 replay changed original payloads or business facts'; END IF;

  SELECT * INTO STRICT input FROM public.fixture_0158_unicode_inputs WHERE kind='blank_both';
  before_error:=pg_temp.fixture_database_state();
  BEGIN
    PERFORM 1 FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
      context.app_user_id,context.workspace_id,context.project_id,input.request_id,generation,
      2,'active',input.note,'other',U&'\202F'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '22023'
    OR actual_message IS DISTINCT FROM 'unassigned project relationship request payload changed'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error
  THEN RAISE EXCEPTION '0159 changed the original Unicode payload drift conflict or state'; END IF;

  FOR input IN SELECT * FROM (VALUES
    (U&'\00A0','New explanation'),('New note',U&'\202F')
  ) AS fields(note,detail)
  LOOP
    actual_state:=NULL; actual_message:=NULL;
    before_error:=pg_temp.fixture_database_state();
    BEGIN
      PERFORM 1 FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
        context.app_user_id,context.workspace_id,context.project_id,gen_random_uuid(),generation,
        2,'active',input.note,'other',input.detail
      );
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
    END;
    IF actual_state IS DISTINCT FROM '22023'
      OR actual_message IS DISTINCT FROM 'invalid unassigned project relationship request'
      OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error
    THEN RAISE EXCEPTION '0159 allowed new blank text or changed state on rejection'; END IF;
  END LOOP;
END
$function$;
