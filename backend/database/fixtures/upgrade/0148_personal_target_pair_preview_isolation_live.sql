\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0148_personal_target_merge_legacy_activation_isolation'
  THEN RAISE EXCEPTION 'Pair preview isolation upgrade requires the real 0148 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0148_pair_preview_context ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
  '7f498000-0000-4000-8000-000000000001'::uuid AS first_target,
  '7f498000-0000-4000-8000-000000000002'::uuid AS second_target
FROM app_data.bootstrap_personal_context('https://0148-upgrade-pair-preview.example.test','owner') c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0148-upgrade-pair-preview.example.test','owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0148 upgrade preview target','+1 773 555 0149','0148@example.test',c.app_user_id
FROM fixture_0148_pair_preview_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.target_id,t.target_id,c.app_user_id,c.app_user_id
FROM fixture_0148_pair_preview_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

CREATE TEMP TABLE fixture_0148_pair_preview_receipt ON COMMIT DROP AS
SELECT preview.preview_id,preview.first_target_id,preview.first_target_type,
  preview.second_target_id,preview.second_target_type,preview.phone_match,
  preview.first_retention_due_at_utc,preview.second_retention_due_at_utc,
  preview.previewed_at_utc,preview.expires_at_utc
FROM fixture_0148_pair_preview_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0148-upgrade-pair-preview.example.test','owner',c.project_id,c.first_target,c.second_target
) preview;

DO $preview$
DECLARE
  receipt pg_temp.fixture_0148_pair_preview_receipt%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM pg_temp.fixture_0148_pair_preview_receipt;
  IF receipt.preview_id IS NULL OR receipt.first_target_id=receipt.second_target_id
    OR receipt.first_target_type IS DISTINCT FROM 'person'
    OR receipt.second_target_type IS DISTINCT FROM 'person'
    OR NOT receipt.phone_match OR receipt.first_retention_due_at_utc<=receipt.previewed_at_utc
    OR receipt.second_retention_due_at_utc<=receipt.previewed_at_utc
    OR (SELECT count(*) FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id=receipt.preview_id)<>1
    OR (SELECT count(*) FROM app_data.promotion_target_access_events
      WHERE actor_app_user_id=(SELECT app_user_id FROM fixture_0148_pair_preview_context)
        AND occurred_at=receipt.previewed_at_utc AND action='viewed'
        AND promotion_target_id IN (receipt.first_target_id,receipt.second_target_id))<>2
    OR (SELECT count(*) FROM app_private.personal_target_pair_preview_audit_events
      WHERE actor_app_user_id=(SELECT app_user_id FROM fixture_0148_pair_preview_context)
        AND occurred_at_utc=receipt.previewed_at_utc
        AND operation='personal_target_pair_preview' AND outcome='previewed')<>1
  THEN RAISE EXCEPTION '0148 upgrade did not commit exactly one valid pair preview, two viewed rows and one audit'; END IF;
END
$preview$;

CREATE TABLE public.fixture_0148_pair_preview_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);

CREATE TABLE public.fixture_0148_pair_preview_isolation_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0148_pair_preview_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0148_pair_preview_isolation_snapshot%ROWTYPE;
  preview_oid oid := 'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure;
  old_source text;
  actual_source text;
  begin_marker CONSTANT text := E'BEGIN\n';
  begin_position integer;
  guard CONSTANT text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target pair preview requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0148_pair_preview_isolation_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0149 pair preview upgrade verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0149_personal_target_pair_preview_isolation'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0148_pair_preview_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=preview_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0148→0149 changed legacy data or function catalog'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_source
  FROM public.fixture_0148_pair_preview_isolation_catalog WHERE oid=preview_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=preview_oid;
  begin_position := strpos(old_source,begin_marker);
  IF begin_position=0 OR strpos(old_source,guard)<>0
    OR actual_source IS DISTINCT FROM overlay(old_source PLACING guard FROM begin_position+length(begin_marker) FOR 0)
  THEN RAISE EXCEPTION '0148→0149 changed pair preview beyond the exact three-line guard after BEGIN'; END IF;
END
$function$;
