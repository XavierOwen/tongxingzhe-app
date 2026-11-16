\set ON_ERROR_STOP on
\ir shared/database_state.sql

-- Reused by the real 0159 upgrade seed and its later assertion connection.
CREATE FUNCTION pg_temp.fixture_0160_seed(flow integer, contact_key text, label text) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE
  c record; result record; first_target uuid; second_target uuid; preview uuid; generation uuid;
  snapshot jsonb; pending uuid; project_pending uuid; plan jsonb; project_plan jsonb; mixed jsonb;
  assignments jsonb; choices jsonb; project_assignments jsonb := '[]'; project_choices jsonb := '[]'; acknowledgements jsonb := '[]';
  issuer text := 'https://synthetic-0160.example.test'; target_type text := CASE WHEN flow=143 THEN 'institution' ELSE 'person' END;
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context(issuer,label);
  PERFORM app_data.list_personal_project_contexts(issuer,label);
  SELECT (target->>'target_id')::uuid INTO STRICT first_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,target_type,'First','+1 312 555 0160',NULL,'first');
  SELECT (target->>'target_id')::uuid INTO STRICT second_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,target_type,'Second','+1 312 555 0160',NULL,'second');
  snapshot := jsonb_build_object('contactId',contact_key,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
    'reason','Bounded command original','occurredAtUtc','2026-11-01T01:02:03.123456Z','occurredTimeZone','America/Chicago','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb);
  IF flow=142 THEN
    SELECT * INTO STRICT result FROM app_data.apply_contact_submit_v3(c.app_user_id,'entry',1,'contact.submit.v1','0160',label||'-entry',0,
      snapshot||jsonb_build_object('contactId',label||'-entry','targetLinks',jsonb_build_array(jsonb_build_object('targetId',first_target,'targetType',target_type,
        'responseLevel',NULL,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
    IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0160 entry control failed: %',result.result_code; END IF;
  END IF;
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1(issuer,label,c.project_id,first_target,second_target);
  generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,first_target,second_target,first_target,second_target);
  SELECT * INTO STRICT result FROM app_data.apply_contact_submit_v3(c.app_user_id,'submit',1,'contact.submit.v1','0160',contact_key,0,snapshot);
  IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0160 long ordinary submit failed: %',result.result_code; END IF;
  snapshot := snapshot||jsonb_build_object('reason','Bounded command ordinary revise','interestLevel',3);
  SELECT * INTO STRICT result FROM app_data.apply_contact_revise_v3(c.app_user_id,'revise',1,'contact.revise.v1','0160',contact_key,1,snapshot);
  IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0160 long ordinary revise failed: %',result.result_code; END IF;
  pending := app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,contact_key,2,3,'yes',target_type='institution',true);
  assignments := jsonb_build_array(jsonb_build_object('pending_fact_id',pending,'source_target_id',first_target));
  choices := jsonb_build_array(jsonb_build_object('contact_id',contact_key,'source_target_id',first_target,'candidate_kind','pending','pending_fact_id',pending));
  plan := app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,generation);
  IF flow IN (142,143) THEN
    SELECT pending_fact_id INTO STRICT project_pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
      c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,2,'paused','0160 original note','progress_update',NULL);
    project_assignments := jsonb_build_array(jsonb_build_object('pending_fact_id',project_pending,'source_target_id',first_target));
    project_choices := jsonb_build_array(jsonb_build_object('project_id',c.project_id,'source_target_id',first_target,'candidate_kind','pending','pending_fact_id',project_pending));
    project_plan := app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,generation);
    mixed := app_private.plan_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,c.project_id,generation,
      plan->'known_source_plan'->>'fact_fingerprint',plan->>'pending_fingerprint',project_plan->>'pending_fingerprint',assignments,project_assignments);
    plan := mixed->'contact_resolution_plan'; project_plan := mixed->'project_relationship_resolution_plan';
    IF flow=143 THEN acknowledgements := jsonb_build_array(jsonb_build_object('project_id',c.project_id,'source_target_id',first_target,'pending_fact_id',project_pending)); END IF;
  ELSIF flow=130 THEN
    plan := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,c.project_id,generation,
      plan->'known_source_plan'->>'fact_fingerprint',plan->>'pending_fingerprint',assignments);
  END IF;
  RETURN to_jsonb(c)||jsonb_build_object('flow',flow,'contact_id',contact_key,'generation_id',generation,'request_id',gen_random_uuid(),
    'pending_fact_id',pending,'source_target_id',first_target,'target_type',target_type,'snapshot',snapshot,'plan',plan,'project_plan',project_plan,'mixed',mixed,
    'assignments',assignments,'choices',choices,'project_assignments',project_assignments,'project_choices',project_choices,'acknowledgements',acknowledgements,
    'old_revisions',(SELECT jsonb_agg(to_jsonb(revision) ORDER BY revision_number) FROM app_data.contact_revisions revision WHERE contact_id=contact_key));
END
$function$;

CREATE FUNCTION pg_temp.fixture_0160_confirm(c jsonb) RETURNS timestamptz LANGUAGE plpgsql AS $function$
DECLARE actor uuid := (c->>'app_user_id')::uuid; workspace uuid := (c->>'workspace_id')::uuid; project uuid := (c->>'project_id')::uuid;
  request uuid := (c->>'request_id')::uuid; generation uuid := (c->>'generation_id')::uuid; p jsonb := c->'plan';
BEGIN
  CASE (c->>'flow')::integer
    WHEN 128 THEN RETURN app_private.confirm_unassigned_personal_merge_contacts_v1(actor,workspace,project,request,generation,
      p->'known_source_plan'->>'fact_fingerprint',p->>'pending_fingerprint',c->'assignments');
    WHEN 130 THEN RETURN app_private.confirm_personal_merge_contact_resolutions_v1(actor,workspace,project,request,generation,
      p->'known_source_plan'->>'fact_fingerprint',p->>'pending_fingerprint',p->>'resolution_fingerprint',c->'assignments',c->'choices');
    WHEN 142 THEN RETURN app_private.confirm_personal_merge_mixed_resolutions_v1(actor,workspace,project,request,generation,
      p->'known_source_plan'->>'fact_fingerprint',p->>'pending_fingerprint',c->'project_plan'->>'pending_fingerprint',c->'mixed'->>'resolution_fingerprint',
      c->'assignments',c->'choices',c->'project_assignments',c->'project_choices');
    WHEN 143 THEN RETURN app_private.confirm_personal_merge_mixed_resolutions_v2(actor,workspace,project,request,generation,
      p->'known_source_plan'->>'fact_fingerprint',p->>'pending_fingerprint',c->'project_plan'->>'pending_fingerprint',c->'mixed'->>'resolution_fingerprint',
      c->'assignments',c->'choices',c->'project_assignments',c->'project_choices',c->'acknowledgements');
    ELSE RAISE EXCEPTION '0160 unknown flow';
  END CASE;
END
$function$;

CREATE FUNCTION pg_temp.fixture_0160_assert(c jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE completed timestamptz; before_replay jsonb; command_id text; flow integer := (c->>'flow')::integer; contact_key text := c->>'contact_id';
BEGIN
  completed := pg_temp.fixture_0160_confirm(c);
  IF completed IS NULL OR NOT EXISTS (SELECT 1 FROM app_data.contacts contact
    JOIN app_data.contact_target_links link ON link.contact_id=contact.contact_id AND link.revision_number=contact.current_revision
    JOIN app_data.contact_revisions revision ON revision.contact_id=contact.contact_id AND revision.revision_number=contact.current_revision
    WHERE contact.contact_id=contact_key AND link.promotion_target_id=(c->>'source_target_id')::uuid
      AND link.response_level=3 AND link.follow_up_consent='yes' AND link.institution_representative_confirmed=(c->>'target_type'='institution')
      AND link.confirmed_project_entry AND revision.snapshot->>'occurredAtUtc'=c->'snapshot'->>'occurredAtUtc'
      AND revision.snapshot->'location'=c->'snapshot'->'location' AND revision.snapshot->'answers'=c->'snapshot'->'answers'
      AND revision.snapshot->'interestLevel'=c->'snapshot'->'interestLevel')
    OR (SELECT jsonb_agg(to_jsonb(revision) ORDER BY revision_number) FROM app_data.contact_revisions revision
      WHERE contact_id=contact_key AND revision_number<=2) IS DISTINCT FROM c->'old_revisions'
    OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id=(c->>'pending_fact_id')::uuid)
  THEN RAISE EXCEPTION '0160 flow % changed contact ID, old revisions, source values, or current facts',flow; END IF;
  IF flow=128 THEN
    SELECT child_command_id INTO STRICT command_id FROM app_private.personal_merge_contact_applications_v1 WHERE pending_fact_id=(c->>'pending_fact_id')::uuid;
  ELSE
    SELECT child_command_id INTO STRICT command_id FROM app_private.personal_merge_contact_current_revisions_v1 WHERE actor_app_user_id=(c->>'app_user_id')::uuid AND request_id=(c->>'request_id')::uuid AND contact_id=contact_key;
  END IF;
  IF command_id IS DISTINCT FROM ((CASE WHEN flow=128 THEN 'personal-merge-contact-confirm-v1:'||(c->>'request_id')||':'
    ELSE 'personal-merge-contact-resolve-v1:'||(c->>'request_id')||':current:' END)
    || CASE WHEN octet_length(contact_key)<=2048 THEN octet_length(contact_key)||':'||contact_key
      ELSE 'sha256-v2:'||encode(sha256(convert_to(contact_key,'UTF8')),'hex') END)
  THEN RAISE EXCEPTION '0160 flow % child command changed the v1 suffix or used a wrong bounded key',flow; END IF;
  before_replay := pg_temp.fixture_database_state();
  IF pg_temp.fixture_0160_confirm(c) IS DISTINCT FROM completed OR pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0160 flow % exact replay changed its receipt or database',flow;
  END IF;
END
$function$;

CREATE FUNCTION pg_temp.fixture_0160_occupied(c jsonb, legacy boolean) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE command_key text; before_error jsonb; actual text; contact_key text := c->>'contact_id';
BEGIN
  command_key := CASE WHEN (c->>'flow')::integer=128 THEN 'personal-merge-contact-confirm-v1:'||(c->>'request_id')||':'
    ELSE 'personal-merge-contact-resolve-v1:'||(c->>'request_id')||':current:' END
    || CASE WHEN legacy THEN octet_length(contact_key)||':'||contact_key
      ELSE 'sha256-v2:'||encode(sha256(convert_to(contact_key,'UTF8')),'hex') END;
  BEGIN
    -- Deliberate synthetic preoccupied receipt, matching the existing 0128/0130 conflict fixtures.
    INSERT INTO app_data.processed_commands(app_user_id,command_id,protocol_version,command_type,device_id,aggregate_id,result_code,server_cursor)
    VALUES((c->>'app_user_id')::uuid,command_key,1,'contact.revise.v1','0160-occupied',contact_key,'accepted',gen_random_uuid());
    before_error := pg_temp.fixture_database_state();
    BEGIN PERFORM pg_temp.fixture_0160_confirm(c);
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
    IF actual IS DISTINCT FROM '23505' OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error THEN
      RAISE EXCEPTION '0160 flow % occupied legacy=% lost conflict or changed state: %',c->>'flow',legacy,actual;
    END IF;
    RAISE EXCEPTION USING ERRCODE='P0160',MESSAGE='rollback synthetic occupied receipt';
  EXCEPTION WHEN SQLSTATE 'P0160' THEN NULL;
  END;
END
$function$;
CREATE FUNCTION pg_temp.fixture_0160_end_fault() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='0160 injected late end failure'; END
$function$;

\if :{?fixture_0160_definitions_only}
\else
BEGIN;
SET LOCAL TIME ZONE 'UTC';
-- First discriminator: valid ordinary data must reach a successful confirmation.
DO $first_confirmation$
DECLARE contact_key text;
BEGIN
  SELECT left(string_agg(md5(i::text),'' ORDER BY i),2600) INTO contact_key FROM generate_series(1,100) i;
  PERFORM pg_temp.fixture_0160_assert(pg_temp.fixture_0160_seed(128,contact_key,'first-confirmation'));
END
$first_confirmation$;
DO $regression$
DECLARE flow integer; c jsonb; contact_key text; n integer; before_error jsonb; actual text;
BEGIN
  FOREACH flow IN ARRAY ARRAY[128,130,142,143] LOOP
    FOREACH n IN ARRAY ARRAY[2600,64,2048,2049] LOOP
      SELECT left(string_agg(md5(flow||'/'||n||'/'||i),'' ORDER BY i),n) INTO contact_key FROM generate_series(1,100) i;
      IF n=2049 THEN contact_key := left(contact_key,2046)||'汉'; END IF;
      c := pg_temp.fixture_0160_seed(flow,contact_key,flow||'-'||n);
      IF n=2600 THEN
        PERFORM pg_temp.fixture_0160_occupied(c,false);
        CREATE TRIGGER fixture_0160_end_fault BEFORE INSERT ON app_private.personal_target_merge_end_events_v1
          FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0160_end_fault();
        before_error := pg_temp.fixture_database_state(); actual := NULL;
        BEGIN PERFORM pg_temp.fixture_0160_confirm(c);
        EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
        IF actual IS DISTINCT FROM '23514' OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error THEN
          RAISE EXCEPTION '0160 flow % late failure did not roll back all children and receipts: %',flow,actual;
        END IF;
        DROP TRIGGER fixture_0160_end_fault ON app_private.personal_target_merge_end_events_v1;
      END IF;
      PERFORM pg_temp.fixture_0160_assert(c);
      before_error := pg_temp.fixture_database_state(); actual := NULL;
      BEGIN
        PERFORM pg_temp.fixture_0160_confirm(jsonb_set(c,'{assignments,0,source_target_id}',to_jsonb(gen_random_uuid())));
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
      IF actual IS DISTINCT FROM '23505' OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error THEN
        RAISE EXCEPTION '0160 flow % terminal typed drift changed state or conflict: %',flow,actual;
      END IF;
    END LOOP;
    c := pg_temp.fixture_0160_seed(flow,flow||repeat('x',2600),flow||'-legacy-occupied');
    PERFORM pg_temp.fixture_0160_occupied(c,true);
    PERFORM pg_temp.fixture_0160_assert(c);
  END LOOP;
END
$regression$;
ROLLBACK;
\endif
