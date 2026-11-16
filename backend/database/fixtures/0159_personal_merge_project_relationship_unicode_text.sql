\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
\ir shared/database_state.sql

CREATE TEMP TABLE fixture_0159_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0159.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0159.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0159_targets ON COMMIT DROP AS
SELECT name.value AS name, created.target
FROM fixture_0159_context context CROSS JOIN (VALUES('first'),('second')) name(value)
CROSS JOIN LATERAL app_data.create_promotion_target(
  context.app_user_id,context.workspace_id,context.project_id,'person','0159 ' || name.value,
  '+1-555-0159',NULL,'0159-' || name.value
) created;
CREATE TEMP TABLE fixture_0159_preview ON COMMIT DROP AS
SELECT preview.* FROM fixture_0159_context context
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://synthetic-0159.example.test','owner',context.project_id,
  (SELECT (target->>'target_id')::uuid FROM fixture_0159_targets WHERE name='first'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0159_targets WHERE name='second')
) preview;
CREATE TEMP TABLE fixture_0159_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  context.app_user_id,context.project_id,gen_random_uuid(),preview.preview_id,
  (SELECT (target->>'target_id')::uuid FROM fixture_0159_targets WHERE name='first'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0159_targets WHERE name='first'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0159_targets WHERE name='second'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0159_targets WHERE name='first')
) AS id FROM fixture_0159_context context CROSS JOIN fixture_0159_preview preview;

CREATE FUNCTION pg_temp.expect_0159_rejection(note text,reason text,detail text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; actual_message text;
BEGIN
  BEGIN
    PERFORM 1 FROM fixture_0159_context context CROSS JOIN fixture_0159_generation generation
    CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(
      context.app_user_id,context.workspace_id,context.project_id,gen_random_uuid(),generation.id,
      2,'active',note,reason,detail) result;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '22023'
    OR actual_message IS DISTINCT FROM 'invalid unassigned project relationship request' THEN
    RAISE EXCEPTION '0159 expected blank-text rejection 22023, got % / %',actual_state,actual_message;
  END IF;
END
$function$;

DO $first_real_rejection$
DECLARE before_state jsonb := pg_temp.fixture_database_state();
BEGIN
  PERFORM pg_temp.expect_0159_rejection(NULL,'other',U&'\00A0');
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_state THEN
    RAISE EXCEPTION '0159 rejected NBSP-only detail changed database state';
  END IF;
END
$first_real_rejection$;

CREATE TEMP TABLE fixture_0159_whitespace ON COMMIT DROP AS
SELECT U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF' AS edge;
DO $every_blank_character$
DECLARE
  before_state jsonb := pg_temp.fixture_database_state();
  edge text := (SELECT whitespace.edge FROM fixture_0159_whitespace whitespace);
  index integer;
BEGIN
  FOR index IN 1..length(edge) LOOP
    PERFORM pg_temp.expect_0159_rejection(substr(edge,index,1),'progress_update',NULL);
    PERFORM pg_temp.expect_0159_rejection(NULL,'other',substr(edge,index,1));
  END LOOP;
  PERFORM pg_temp.expect_0159_rejection(edge,'progress_update',NULL);
  PERFORM pg_temp.expect_0159_rejection(NULL,'other',edge);
  PERFORM pg_temp.expect_0159_rejection('','progress_update',NULL);
  PERFORM pg_temp.expect_0159_rejection(NULL,'other','');
  PERFORM pg_temp.expect_0159_rejection(NULL,'other',NULL);
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_state THEN
    RAISE EXCEPTION '0159 blank note/detail rejection changed pending values, history, or fence';
  END IF;
END
$every_blank_character$;

CREATE TEMP TABLE fixture_0159_raw_text ON COMMIT DROP AS
SELECT edge || E'Note\t  with' || U&'\00A0inside' || edge AS note,
  edge || E'Detail\nwith' || U&'\202Finside' || edge AS detail
FROM fixture_0159_whitespace;
CREATE TEMP TABLE fixture_0159_meaningful ON COMMIT DROP AS
SELECT result.* FROM fixture_0159_context context CROSS JOIN fixture_0159_generation generation
CROSS JOIN fixture_0159_raw_text raw
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(
  context.app_user_id,context.workspace_id,context.project_id,'00000000-0159-6000-8000-000000000001',generation.id,
  2,'active',raw.note,'other',raw.detail) result;
CREATE TEMP TABLE fixture_0159_optional_null ON COMMIT DROP AS
SELECT result.* FROM fixture_0159_context context CROSS JOIN fixture_0159_generation generation
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(
  context.app_user_id,context.workspace_id,context.project_id,'00000000-0159-6000-8000-000000000002',generation.id,
  3,'paused',NULL,'target_request',NULL) result;

DO $raw_values_and_exact_replay$
DECLARE
  before_state jsonb := pg_temp.fixture_database_state() - 'app_private.personal_target_merge_generation_fence_v1';
  before_drift jsonb;
  replayed jsonb;
  drift_state text;
  drift_message text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0159_meaningful receipt
    JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 fact USING(pending_fact_id)
    CROSS JOIN fixture_0159_raw_text raw
    WHERE fact.new_stage=2 AND fact.new_lifecycle_status='active' AND fact.follow_up_note=raw.note
      AND fact.reason_code='other' AND fact.reason_detail=raw.detail)
    OR NOT EXISTS (SELECT 1 FROM fixture_0159_optional_null receipt
      JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 fact USING(pending_fact_id)
      WHERE fact.follow_up_note IS NULL AND fact.reason_detail IS NULL AND fact.reason_code='target_request') THEN
    RAISE EXCEPTION '0159 meaningful raw text or legal optional NULL values changed';
  END IF;
  SELECT to_jsonb(result) INTO STRICT replayed FROM fixture_0159_context context
  CROSS JOIN fixture_0159_generation generation CROSS JOIN fixture_0159_raw_text raw
  CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(
    context.app_user_id,context.workspace_id,context.project_id,'00000000-0159-6000-8000-000000000001',generation.id,
    2,'active',raw.note,'other',raw.detail) result;
  IF replayed IS DISTINCT FROM (SELECT to_jsonb(receipt) FROM fixture_0159_meaningful receipt) THEN
    RAISE EXCEPTION '0159 exact meaningful replay changed its original receipt';
  END IF;
  -- The existing successful stage replay advances only the generation fence epoch.
  IF pg_temp.fixture_database_state() - 'app_private.personal_target_merge_generation_fence_v1' IS DISTINCT FROM before_state THEN
    RAISE EXCEPTION '0159 exact replay changed business state';
  END IF;
  before_drift := pg_temp.fixture_database_state();
  BEGIN
    PERFORM 1 FROM fixture_0159_context context CROSS JOIN fixture_0159_generation generation
    CROSS JOIN fixture_0159_raw_text raw
    CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(
      context.app_user_id,context.workspace_id,context.project_id,'00000000-0159-6000-8000-000000000001',generation.id,
      2,'active',raw.note || 'changed','other',raw.detail) result;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS drift_state=RETURNED_SQLSTATE,drift_message=MESSAGE_TEXT;
  END;
  IF drift_state IS DISTINCT FROM '22023'
    OR drift_message IS DISTINCT FROM 'unassigned project relationship request payload changed' THEN
    RAISE EXCEPTION '0159 payload drift lost original conflict: % / %',drift_state,drift_message;
  END IF;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_drift THEN
    RAISE EXCEPTION '0159 rejected drift changed database state';
  END IF;
END
$raw_values_and_exact_replay$;

ROLLBACK;
