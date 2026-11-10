\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0149_personal_target_pair_preview_isolation'
  THEN RAISE EXCEPTION 'Unassigned contact stage isolation upgrade requires the real 0149 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0149_contact_stage_context ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,c.questionnaire_version_id,
  '7f508000-0000-4000-8000-000000000001'::uuid AS first_target,
  '7f508000-0000-4000-8000-000000000002'::uuid AS second_target
FROM app_data.bootstrap_personal_context('https://0149-upgrade-contact-stage.example.test','owner') c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0149-upgrade-contact-stage.example.test','owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0149 upgrade contact stage source','+1 773 555 0150','0149@example.test',c.app_user_id
FROM fixture_0149_contact_stage_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.target_id,t.target_id,c.app_user_id,c.app_user_id
FROM fixture_0149_contact_stage_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

CREATE TEMP TABLE fixture_0149_contact_stage_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  c.app_user_id,c.project_id,'7f508000-0000-4000-8000-000000000003',preview.preview_id,
  c.first_target,c.second_target,c.first_target,c.second_target
) AS generation_id
FROM fixture_0149_contact_stage_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0149-upgrade-contact-stage.example.test','owner',c.project_id,c.first_target,c.second_target
) preview;

CREATE TEMP TABLE fixture_0149_contact_stage_contact ON COMMIT DROP AS
SELECT submitted.result_code
FROM fixture_0149_contact_stage_context c
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id,'0149-upgrade-contact-stage-submit',1,'contact.submit.v1','0149-upgrade-contact-stage-device',
  '0149-upgrade-unlinked-contact',0,
  jsonb_build_object('contactId','0149-upgrade-unlinked-contact','workspaceId',c.workspace_id,
    'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
    'reason','0149 pending contact stage','occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC',
    'channel','video_call','location',jsonb_build_object('kind','not_applicable'),
    'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb)
) submitted;

CREATE TEMP TABLE fixture_0149_contact_stage_pending ON COMMIT DROP AS
SELECT app_private.stage_unassigned_personal_merge_contact_v1(
  c.app_user_id,c.workspace_id,c.project_id,'7f508000-0000-4000-8000-000000000004',g.generation_id,
  '0149-upgrade-unlinked-contact',1,2,'unknown',false,true
) AS pending_fact_id
FROM fixture_0149_contact_stage_context c CROSS JOIN fixture_0149_contact_stage_generation g;

DO $pending_baseline$
DECLARE
  c fixture_0149_contact_stage_context%ROWTYPE;
  g fixture_0149_contact_stage_generation%ROWTYPE;
  pending_id uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0149_contact_stage_context;
  SELECT * INTO STRICT g FROM fixture_0149_contact_stage_generation;
  SELECT pending_fact_id INTO STRICT pending_id FROM fixture_0149_contact_stage_pending;
  IF (SELECT result_code FROM fixture_0149_contact_stage_contact) IS DISTINCT FROM 'accepted'
    OR (SELECT current_revision FROM app_data.contacts WHERE contact_id='0149-upgrade-unlinked-contact') IS DISTINCT FROM 1
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links
      WHERE contact_id='0149-upgrade-unlinked-contact' AND revision_number=1)
    OR NOT EXISTS (
      SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 h
      JOIN app_data.personal_merge_unassigned_contact_facts_v1 p USING (pending_fact_id)
      WHERE h.pending_fact_id=pending_id AND h.actor_app_user_id=c.app_user_id
        AND h.workspace_id=c.workspace_id AND h.project_id=c.project_id AND h.generation_id=g.generation_id
        AND h.contact_id='0149-upgrade-unlinked-contact' AND h.revision_number=1 AND h.target_type='person'
        AND h.request_id='7f508000-0000-4000-8000-000000000004' AND h.staged_at_utc IS NOT NULL
        AND p.response_level=2 AND p.follow_up_consent='unknown'
        AND NOT p.institution_representative_confirmed AND p.confirmed_project_entry
    )
    OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1
      WHERE pending_fact_id=pending_id)<>1
    OR (SELECT count(*) FROM app_data.personal_merge_unassigned_contact_facts_v1
      WHERE pending_fact_id=pending_id)<>1
  THEN RAISE EXCEPTION '0149 upgrade did not stage one valid v2-generation unlinked contact header and payload'; END IF;
END
$pending_baseline$;

CREATE TABLE public.fixture_0149_contact_stage_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0149_contact_stage_isolation_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0149_contact_stage_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0149_contact_stage_isolation_snapshot%ROWTYPE;
  stage_oid oid := 'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)'::regprocedure;
  old_source text;
  actual_source text;
  anchor CONSTANT text := '  PERFORM pg_advisory_xact_lock(hashtextextended(';
  anchor_position integer;
  guard CONSTANT text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'unassigned contact staging requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0149_contact_stage_isolation_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0150 unassigned contact stage verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0150_personal_merge_unassigned_contact_stage_isolation'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0149_contact_stage_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=stage_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0149→0150 changed legacy data or function catalog'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_source
  FROM public.fixture_0149_contact_stage_isolation_catalog WHERE oid=stage_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=stage_oid;
  anchor_position := strpos(old_source,anchor);
  IF anchor_position=0 OR strpos(old_source,guard)<>0
    OR length(old_source)-length(replace(old_source,anchor,''))<>length(anchor)
    OR actual_source IS DISTINCT FROM overlay(old_source PLACING guard FROM anchor_position FOR 0)
  THEN RAISE EXCEPTION '0149→0150 changed contact stage beyond the exact three-line guard before the request lock'; END IF;
END
$function$;
