\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0150_personal_merge_unassigned_contact_stage_isolation'
  THEN RAISE EXCEPTION 'Authorized projection isolation upgrade requires the real 0150 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0150_projection_context ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
  'https://0150-authorized-projection.example.test/auth/v1'::text AS issuer,
  '0150-authorized-projection-owner'::text AS subject,
  '7f518000-0000-4000-8000-000000000001'::uuid AS first_target,
  '7f518000-0000-4000-8000-000000000002'::uuid AS second_target
FROM app_data.bootstrap_personal_context(
  'https://0150-authorized-projection.example.test/auth/v1','0150-authorized-projection-owner'
) c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0150-authorized-projection.example.test/auth/v1','0150-authorized-projection-owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0150 authorized projection source','+1 773 555 0151',
  '0150-projection@example.test',c.app_user_id
FROM fixture_0150_projection_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);
INSERT INTO app_data.promotion_target_assignments(
  assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id
)
SELECT t.target_id,t.target_id,c.app_user_id,c.app_user_id
FROM fixture_0150_projection_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

CREATE TEMP TABLE fixture_0150_projection_generation ON COMMIT DROP AS
SELECT preview.preview_id,
  app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,'7f518000-0000-4000-8000-000000000003',preview.preview_id,
    c.first_target,c.second_target,c.first_target,c.second_target
  ) AS generation_id
FROM fixture_0150_projection_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  c.issuer,c.subject,c.project_id,c.first_target,c.second_target
) preview;

CREATE TEMP TABLE fixture_0150_projection_expected ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,c.issuer,c.subject,
  c.first_target,c.second_target,g.preview_id,g.generation_id,
  app_private.read_known_source_personal_target_merge_projection_v1(
    c.app_user_id,c.workspace_id,c.project_id,g.generation_id
  ) AS document,
  (SELECT count(*) FROM app_data.promotion_target_access_events WHERE workspace_id=c.workspace_id) AS access_count,
  coalesce((SELECT array_agg(event_id) FROM app_data.promotion_target_access_events
    WHERE workspace_id=c.workspace_id),'{}'::uuid[]) AS access_event_ids
FROM fixture_0150_projection_context c CROSS JOIN fixture_0150_projection_generation g;

CREATE TEMP TABLE fixture_0150_projection_read ON COMMIT DROP AS
SELECT app_private.read_authorized_known_source_personal_merge_projection_v1(
  expected.issuer,expected.subject,expected.project_id,expected.generation_id
) AS document
FROM fixture_0150_projection_expected expected;

CREATE TABLE public.fixture_0150_projection_success AS
SELECT expected.app_user_id,expected.workspace_id,expected.project_id,expected.issuer,expected.subject,
  expected.first_target,expected.second_target,expected.preview_id,expected.generation_id,
  expected.document AS original_document,actual.document AS returned_document,expected.access_count
FROM fixture_0150_projection_expected expected CROSS JOIN fixture_0150_projection_read actual;
CREATE TABLE public.fixture_0150_projection_access_audits AS
SELECT event.* FROM app_data.promotion_target_access_events event
CROSS JOIN fixture_0150_projection_expected expected
WHERE event.workspace_id=expected.workspace_id AND event.actor_app_user_id=expected.app_user_id
  AND event.action='viewed'
  AND event.promotion_target_id IN (expected.first_target,expected.second_target)
  AND NOT (event.event_id=ANY(expected.access_event_ids));

DO $successful_read$
DECLARE saved public.fixture_0150_projection_success%ROWTYPE;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0150_projection_success;
  IF saved.returned_document IS NULL OR saved.returned_document IS DISTINCT FROM saved.original_document
    OR saved.returned_document->>'generation_id' IS DISTINCT FROM saved.generation_id::text
    OR jsonb_array_length(saved.returned_document->'sources')<>2
    OR (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1
      WHERE generation_id=saved.generation_id)<>2
    OR (SELECT count(*) FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id=saved.preview_id)<>1
    OR (SELECT count(*) FROM app_data.promotion_target_access_events
      WHERE workspace_id=saved.workspace_id)<>saved.access_count+2
    OR (SELECT count(*) FROM public.fixture_0150_projection_access_audits)<>2
    OR EXISTS (SELECT 1 FROM public.fixture_0150_projection_access_audits event
      WHERE event.actor_app_user_id IS DISTINCT FROM saved.app_user_id OR event.action IS DISTINCT FROM 'viewed'
        OR event.promotion_target_id NOT IN (saved.first_target,saved.second_target))
  THEN RAISE EXCEPTION '0150 upgrade did not produce the original authorized document, generation/receipt and two source audits'; END IF;
END
$successful_read$;

CREATE TABLE public.fixture_0150_authorized_projection_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0150_authorized_projection_isolation_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0150_authorized_projection_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0150_authorized_projection_isolation_snapshot%ROWTYPE;
  original public.fixture_0150_projection_success%ROWTYPE;
  projection_oid oid := 'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  old_source text;
  actual_source text;
  validation_tail CONSTANT text := $validation$      MESSAGE = 'invalid authorized known-source personal target merge projection request';
  END IF;

$validation$;
  validation_position integer;
  ownership_comment CONSTANT text := '  -- Personal ownership derives both PII-view and merge-management capabilities, as in 0113.';
  guard CONSTANT text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'authorized personal target merge projection requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0150_authorized_projection_isolation_snapshot;
  SELECT * INTO STRICT original FROM public.fixture_0150_projection_success;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0151 authorized projection verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0151_personal_target_authorized_projection_isolation'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0150_authorized_projection_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=projection_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0150→0151 changed business facts or function metadata beyond the isolated body'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_source
  FROM public.fixture_0150_authorized_projection_isolation_catalog WHERE oid=projection_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=projection_oid;
  validation_position := strpos(old_source,validation_tail);
  IF validation_position=0 OR strpos(old_source,validation_tail||ownership_comment)=0
    OR strpos(old_source,guard)<>0
    OR length(old_source)-length(replace(old_source,validation_tail,''))<>length(validation_tail)
    OR actual_source IS DISTINCT FROM overlay(old_source PLACING guard FROM validation_position+length(validation_tail) FOR 0)
  THEN RAISE EXCEPTION '0150→0151 changed authorized projection beyond the exact three-line guard after validation'; END IF;

  IF original.returned_document IS DISTINCT FROM original.original_document
    OR original.returned_document->>'generation_id' IS DISTINCT FROM original.generation_id::text
    OR jsonb_array_length(original.returned_document->'sources')<>2
    OR (SELECT count(*) FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id=original.preview_id)<>1
    OR (SELECT count(*) FROM public.fixture_0150_projection_access_audits)<>2
    OR (SELECT count(*) FROM app_data.promotion_target_access_events live
      JOIN public.fixture_0150_projection_access_audits frozen USING(event_id)
      WHERE to_jsonb(live) IS DISTINCT FROM to_jsonb(frozen))<>0
  THEN RAISE EXCEPTION '0151 altered the saved document, original generation receipt or audited read rows'; END IF;
END
$function$;
