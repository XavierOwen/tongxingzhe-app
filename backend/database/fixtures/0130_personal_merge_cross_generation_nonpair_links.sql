-- Synthetic independent merge generations preserve old bindings and new ordinary-writer facts.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL TIME ZONE 'UTC';
\ir shared/database_state.sql

DO $fixture$
DECLARE
  c record;
  created record;
  applied record;
  target_ids uuid[] := ARRAY[]::uuid[];
  target_number integer;
  preview_a uuid;
  preview_b uuid;
  generation_a uuid;
  generation_b uuid;
  pending_id uuid;
  confirmation_request uuid := gen_random_uuid();
  pending_plan jsonb;
  resolution_plan jsonb;
  assignments jsonb;
  choices jsonb;
  original_b_link jsonb;
  original_revision jsonb;
  before_b_count bigint;
  before_b_fingerprint text;
  after_b_count bigint;
  after_b_fingerprint text;
  confirmed_at timestamptz;
  replayed_at timestamptz;
  before_replay jsonb;
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context(
    'https://synthetic-0130-cross-generation.example.test', '0130-cross-generation-owner');
  IF NOT EXISTS (SELECT 1 FROM app_data.list_personal_project_contexts(
      'https://synthetic-0130-cross-generation.example.test', '0130-cross-generation-owner') context
      WHERE context.is_current AND context.app_user_id=c.app_user_id
        AND context.workspace_id=c.workspace_id AND context.project_id=c.project_id) THEN
    RAISE EXCEPTION '0130-cross-generation own current context is missing';
  END IF;

  FOR target_number IN 1..4 LOOP
    SELECT * INTO STRICT created FROM app_data.create_promotion_target(
      c.app_user_id,c.workspace_id,c.project_id,'person',
      '0130-cross-generation source '||target_number,
      CASE WHEN target_number<=2 THEN '+1 312 555 7111' ELSE '+1 312 555 7222' END,
      NULL,'0130-cross-generation-create-'||target_number);
    target_ids := array_append(target_ids,(created.target->>'target_id')::uuid);
  END LOOP;

  SELECT preview_id INTO STRICT preview_a FROM app_data.preview_personal_target_pair_v1(
    'https://synthetic-0130-cross-generation.example.test','0130-cross-generation-owner',c.project_id,target_ids[1],target_ids[2]);
  generation_a := app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,gen_random_uuid(),preview_a,
    target_ids[1],target_ids[1],target_ids[1],target_ids[2]);

  SELECT * INTO STRICT applied FROM app_data.apply_contact_submit_v3(
    c.app_user_id,'0130-cross-generation-submit',1,'contact.submit.v1','0130-cross-generation-device',
    '0130-cross-generation-contact',0,jsonb_build_object(
      'contactId','0130-cross-generation-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
      'questionnaireVersionId',c.questionnaire_version_id,
      'occurredAtUtc','2025-05-03T04:05:06.123456Z','occurredTimeZone','UTC',
      'channel','voice_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',2,'interestLevel',3,'answers','[]'::jsonb,
      'targetLinks',jsonb_build_array(jsonb_build_object(
        'targetId',target_ids[3],'targetType','person','responseLevel',1,
        'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
  IF applied.result_code IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION '0130-cross-generation ordinary submit rejected: %',row_to_json(applied);
  END IF;
  SELECT to_jsonb(link) INTO STRICT original_b_link FROM app_data.contact_target_links link
    WHERE link.contact_id='0130-cross-generation-contact' AND link.revision_number=1
      AND link.promotion_target_id=target_ids[3];
  SELECT to_jsonb(revision) INTO STRICT original_revision FROM app_data.contact_revisions revision
    WHERE revision.contact_id='0130-cross-generation-contact' AND revision.revision_number=1;
  IF original_b_link->>'merge_generation_id' IS NOT NULL THEN
    RAISE EXCEPTION '0130-cross-generation B1 original link unexpectedly has a generation';
  END IF;

  pending_id := app_private.stage_unassigned_personal_merge_contact_v1(
    c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation_a,
    '0130-cross-generation-contact',1,4,'yes',false,true);

  SELECT preview_id INTO STRICT preview_b FROM app_data.preview_personal_target_pair_v1(
    'https://synthetic-0130-cross-generation.example.test','0130-cross-generation-owner',c.project_id,target_ids[3],target_ids[4]);
  generation_b := app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,gen_random_uuid(),preview_b,
    target_ids[3],target_ids[3],target_ids[3],target_ids[4]);
  SELECT fact_count,fact_fingerprint INTO STRICT before_b_count,before_b_fingerprint
    FROM app_private.personal_target_merge_known_source_manifest_v1(generation_b);
  IF (SELECT to_jsonb(link) FROM app_data.contact_target_links link
      WHERE link.contact_id='0130-cross-generation-contact' AND link.revision_number=1
        AND link.promotion_target_id=target_ids[3]) IS DISTINCT FROM original_b_link THEN
    RAISE EXCEPTION '0130-cross-generation B activation changed the old B1 link';
  END IF;

  pending_plan := app_private.read_personal_merge_unassigned_contact_plan_v1(
    c.app_user_id,c.workspace_id,c.project_id,generation_a);
  assignments := jsonb_build_array(jsonb_build_object('pending_fact_id',pending_id,'source_target_id',target_ids[1]));
  resolution_plan := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(
    c.app_user_id,c.workspace_id,c.project_id,generation_a,
    pending_plan->'known_source_plan'->>'fact_fingerprint',pending_plan->>'pending_fingerprint',assignments);
  SELECT jsonb_agg(jsonb_build_object('contact_id',slot->>'contact_id',
    'source_target_id',slot->>'source_target_id','candidate_kind','pending',
    'pending_fact_id',slot->'pending_fact_ids'->>0)
    ORDER BY slot->>'contact_id' COLLATE "C",(slot->>'source_target_id')::uuid)
  INTO choices FROM jsonb_array_elements(resolution_plan->'source_slots') slot;
  IF jsonb_array_length(resolution_plan->'source_slots')<>1
    OR choices->0->>'pending_fact_id' IS DISTINCT FROM pending_id::text THEN
    RAISE EXCEPTION '0130-cross-generation A plan lost the sole explicit source choice';
  END IF;
  confirmed_at := app_private.confirm_personal_merge_contact_resolutions_v1(
    c.app_user_id,c.workspace_id,c.project_id,confirmation_request,generation_a,
    resolution_plan->'known_source_plan'->>'fact_fingerprint',resolution_plan->>'pending_fingerprint',
    resolution_plan->>'resolution_fingerprint',assignments,choices);

  IF confirmed_at IS NULL
    OR NOT app_private.personal_merge_contact_resolution_proof_v1(c.app_user_id,confirmation_request)
    OR (SELECT current_revision FROM app_data.contacts WHERE contact_id='0130-cross-generation-contact')<>3
    OR (SELECT to_jsonb(revision) FROM app_data.contact_revisions revision
      WHERE revision.contact_id='0130-cross-generation-contact' AND revision.revision_number=1) IS DISTINCT FROM original_revision
    OR (SELECT to_jsonb(link) FROM app_data.contact_target_links link
      WHERE link.contact_id='0130-cross-generation-contact' AND link.revision_number=1
        AND link.promotion_target_id=target_ids[3]) IS DISTINCT FROM original_b_link
    OR (SELECT count(*) FROM app_data.contact_target_links link
      WHERE link.contact_id='0130-cross-generation-contact' AND link.revision_number IN (2,3)
        AND link.promotion_target_id=target_ids[3] AND link.merge_generation_id=generation_b
        AND to_jsonb(link)-ARRAY['revision_number','merge_generation_id']
          =original_b_link-ARRAY['revision_number','merge_generation_id'])<>2
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=generation_a)
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=generation_b)<>2
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1
      WHERE generation_id=generation_a AND request_id=confirmation_request AND ended_at_utc=confirmed_at)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=generation_b) THEN
    RAISE EXCEPTION '0130-cross-generation A confirmation lost history, B business facts, binding, or independent lifecycle';
  END IF;
  SELECT fact_count,fact_fingerprint INTO STRICT after_b_count,after_b_fingerprint
    FROM app_private.personal_target_merge_known_source_manifest_v1(generation_b);
  IF after_b_count<>before_b_count+2 OR after_b_fingerprint=before_b_fingerprint THEN
    RAISE EXCEPTION '0130-cross-generation B manifest did not gain the two new B1 contact facts';
  END IF;

  before_replay := pg_temp.fixture_database_state();
  replayed_at := app_private.confirm_personal_merge_contact_resolutions_v1(
    c.app_user_id,c.workspace_id,c.project_id,confirmation_request,generation_a,
    resolution_plan->'known_source_plan'->>'fact_fingerprint',resolution_plan->>'pending_fingerprint',
    resolution_plan->>'resolution_fingerprint',assignments,choices);
  IF replayed_at IS DISTINCT FROM confirmed_at OR pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0130-cross-generation A terminal replay changed its original time or persistent business state';
  END IF;
  RAISE NOTICE '0130-cross-generation fixture passed: A ended, B active, old NULL binding retained, two new B-bound facts, exact replay unchanged';
END
$fixture$;
ROLLBACK;
