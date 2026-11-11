\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0151_personal_target_authorized_projection_isolation'
  THEN RAISE EXCEPTION 'Audited merge metadata isolation upgrade requires the real 0151 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0151_audited_metadata_context ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
  'https://0151-audited-metadata.example.test/auth/v1'::text AS issuer,
  '0151-audited-metadata-owner'::text AS subject,
  '7f528000-0000-4000-8000-000000000001'::uuid AS first_target,
  '7f528000-0000-4000-8000-000000000002'::uuid AS second_target
FROM app_data.bootstrap_personal_context(
  'https://0151-audited-metadata.example.test/auth/v1','0151-audited-metadata-owner'
) c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0151-audited-metadata.example.test/auth/v1','0151-audited-metadata-owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0151 audited metadata source','+1 773 555 0152',
  '0151-audited-metadata@example.test',c.app_user_id
FROM fixture_0151_audited_metadata_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);
INSERT INTO app_data.promotion_target_assignments(
  assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id
)
SELECT t.target_id,t.target_id,c.app_user_id,c.app_user_id
FROM fixture_0151_audited_metadata_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

CREATE TEMP TABLE fixture_0151_audited_metadata_generation ON COMMIT DROP AS
SELECT preview.preview_id,
  app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,'7f528000-0000-4000-8000-000000000003',preview.preview_id,
    c.first_target,c.second_target,c.first_target,c.second_target
  ) AS generation_id
FROM fixture_0151_audited_metadata_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  c.issuer,c.subject,c.project_id,c.first_target,c.second_target
) preview;

CREATE TEMP TABLE fixture_0151_audited_metadata_expected ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,c.issuer,c.subject,
  c.first_target,c.second_target,g.preview_id,g.generation_id,
  app_private.read_known_source_personal_merge_split_plan_v1(
    c.app_user_id,c.workspace_id,c.project_id,g.generation_id
  ) AS split_plan_document,
  (SELECT count(*) FROM app_data.promotion_target_access_events WHERE workspace_id=c.workspace_id) AS access_count,
  coalesce((SELECT array_agg(event_id) FROM app_data.promotion_target_access_events
    WHERE workspace_id=c.workspace_id),'{}'::uuid[]) AS access_event_ids
FROM fixture_0151_audited_metadata_context c
CROSS JOIN fixture_0151_audited_metadata_generation g;

CREATE TEMP TABLE fixture_0151_audited_split_plan_read ON COMMIT DROP AS
SELECT app_private.read_authorized_known_source_merge_split_plan_v1(
  expected.issuer,expected.subject,expected.project_id,expected.generation_id
) AS document
FROM fixture_0151_audited_metadata_expected expected;
CREATE TEMP TABLE fixture_0151_audited_directory_read ON COMMIT DROP AS
SELECT app_private.read_authorized_personal_merge_directory_v1(
  expected.issuer,expected.subject,expected.project_id,NULL
) AS document
FROM fixture_0151_audited_metadata_expected expected;

CREATE TABLE public.fixture_0151_audited_metadata_success AS
SELECT expected.app_user_id,expected.workspace_id,expected.project_id,expected.issuer,expected.subject,
  expected.first_target,expected.second_target,expected.preview_id,expected.generation_id,
  expected.split_plan_document,split_read.document AS audited_split_plan_document,
  directory_read.document AS audited_directory_document,expected.access_count
FROM fixture_0151_audited_metadata_expected expected
CROSS JOIN fixture_0151_audited_split_plan_read split_read
CROSS JOIN fixture_0151_audited_directory_read directory_read;
CREATE TABLE public.fixture_0151_audited_metadata_access_audits AS
SELECT event.* FROM app_data.promotion_target_access_events event
CROSS JOIN fixture_0151_audited_metadata_expected expected
WHERE event.workspace_id=expected.workspace_id AND event.actor_app_user_id=expected.app_user_id
  AND event.action='viewed'
  AND event.promotion_target_id IN (expected.first_target,expected.second_target)
  AND NOT (event.event_id=ANY(expected.access_event_ids));

-- A new pair can have no contact or relationship facts.
DO $successful_reads$
DECLARE saved public.fixture_0151_audited_metadata_success%ROWTYPE;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0151_audited_metadata_success;
  IF saved.split_plan_document IS NULL
    OR saved.split_plan_document->'member_target_ids' IS DISTINCT FROM
      jsonb_build_array(saved.first_target,saved.second_target)
    OR (saved.split_plan_document->>'fact_count')::integer IS DISTINCT FROM
      jsonb_array_length(saved.split_plan_document->'facts')
    OR saved.audited_split_plan_document IS DISTINCT FROM saved.split_plan_document
    OR saved.audited_split_plan_document->>'generation_id' IS DISTINCT FROM saved.generation_id::text
    OR saved.audited_directory_document->>'workspace_id' IS DISTINCT FROM saved.workspace_id::text
    OR saved.audited_directory_document->>'project_id' IS DISTINCT FROM saved.project_id::text
    OR jsonb_array_length(saved.audited_directory_document->'items')<>1
    OR saved.audited_directory_document->'items'->0->>'generation_id' IS DISTINCT FROM saved.generation_id::text
    OR (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1
      WHERE generation_id=saved.generation_id)<>2
    OR (SELECT count(*) FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id=saved.preview_id)<>1
    OR (SELECT count(*) FROM app_data.promotion_target_access_events
      WHERE workspace_id=saved.workspace_id)<>saved.access_count+4
    OR (SELECT count(*) FROM public.fixture_0151_audited_metadata_access_audits)<>4
    OR (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id)
      FROM public.fixture_0151_audited_metadata_access_audits)
      IS DISTINCT FROM ARRAY[saved.first_target,saved.first_target,saved.second_target,saved.second_target]::uuid[]
    OR EXISTS (SELECT 1 FROM public.fixture_0151_audited_metadata_access_audits event
      WHERE event.actor_app_user_id IS DISTINCT FROM saved.app_user_id OR event.action IS DISTINCT FROM 'viewed')
  THEN RAISE EXCEPTION '0151 upgrade did not retain the original split plan, directory, generation/receipt and four source audits'; END IF;
END
$successful_reads$;

CREATE TABLE public.fixture_0151_audited_metadata_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0151_audited_metadata_isolation_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0151_audited_metadata_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0151_audited_metadata_isolation_snapshot%ROWTYPE;
  original public.fixture_0151_audited_metadata_success%ROWTYPE;
  split_oid oid := 'app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure;
  directory_oid oid := 'app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid)'::regprocedure;
  old_split_source text;
  actual_split_source text;
  old_directory_source text;
  actual_directory_source text;
  anchor CONSTANT text := '  WITH context AS MATERIALIZED (';
  split_validation_tail CONSTANT text := $split_validation$      MESSAGE = 'invalid authorized known-source merge split plan request';
  END IF;

$split_validation$;
  directory_begin_marker CONSTANT text := E'BEGIN\n';
  split_guard CONSTANT text := $split_guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'authorized personal merge split plan requires read committed';
  END IF;
$split_guard$;
  directory_guard CONSTANT text := $directory_guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'authorized personal merge directory requires read committed';
  END IF;
$directory_guard$;
  split_anchor_position integer;
  directory_anchor_position integer;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0151_audited_metadata_isolation_snapshot;
  SELECT * INTO STRICT original FROM public.fixture_0151_audited_metadata_success;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0152 audited metadata verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0152_personal_target_audited_merge_metadata_isolation'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0151_audited_metadata_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid IN (split_oid,directory_oid)
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0151→0152 changed business facts or function metadata beyond the two isolated bodies'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_split_source
  FROM public.fixture_0151_audited_metadata_isolation_catalog WHERE oid=split_oid;
  SELECT prosrc INTO STRICT actual_split_source FROM pg_catalog.pg_proc WHERE oid=split_oid;
  split_anchor_position := strpos(old_split_source,anchor);
  SELECT catalog_row->>'prosrc' INTO STRICT old_directory_source
  FROM public.fixture_0151_audited_metadata_isolation_catalog WHERE oid=directory_oid;
  SELECT prosrc INTO STRICT actual_directory_source FROM pg_catalog.pg_proc WHERE oid=directory_oid;
  directory_anchor_position := strpos(old_directory_source,anchor);
  IF split_anchor_position=0 OR directory_anchor_position=0
    OR strpos(old_split_source,split_validation_tail||anchor)=0
    OR strpos(old_directory_source,directory_begin_marker||anchor)=0
    OR strpos(old_split_source,split_guard)<>0 OR strpos(old_directory_source,directory_guard)<>0
    OR length(old_split_source)-length(replace(old_split_source,anchor,''))<>length(anchor)
    OR length(old_directory_source)-length(replace(old_directory_source,anchor,''))<>length(anchor)
    OR actual_split_source IS DISTINCT FROM overlay(old_split_source PLACING split_guard FROM split_anchor_position FOR 0)
    OR actual_directory_source IS DISTINCT FROM overlay(old_directory_source PLACING directory_guard FROM directory_anchor_position FOR 0)
  THEN RAISE EXCEPTION '0151→0152 changed audited split-plan/directory beyond their exact three-line guards'; END IF;

  IF original.audited_split_plan_document IS DISTINCT FROM original.split_plan_document
    OR original.split_plan_document->'member_target_ids' IS DISTINCT FROM
      jsonb_build_array(original.first_target,original.second_target)
    OR original.audited_directory_document->>'workspace_id' IS DISTINCT FROM original.workspace_id::text
    OR original.audited_directory_document->>'project_id' IS DISTINCT FROM original.project_id::text
    OR original.audited_directory_document->'items'->0->>'generation_id' IS DISTINCT FROM original.generation_id::text
    OR (SELECT count(*) FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id=original.preview_id)<>1
    OR (SELECT count(*) FROM public.fixture_0151_audited_metadata_access_audits)<>4
    OR (SELECT count(*) FROM app_data.promotion_target_access_events live
      JOIN public.fixture_0151_audited_metadata_access_audits frozen USING(event_id)
      WHERE to_jsonb(live) IS DISTINCT FROM to_jsonb(frozen))<>0
  THEN RAISE EXCEPTION '0152 altered saved split plan/directory documents or original generation receipt/audits'; END IF;
END
$function$;
