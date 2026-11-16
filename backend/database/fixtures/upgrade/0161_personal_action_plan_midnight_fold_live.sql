\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) IS DISTINCT FROM '0161_personal_merge_contact_metadata_keys' THEN
    RAISE EXCEPTION 'personal plan midnight upgrade requires the real 0161 baseline';
  END IF;
END
$baseline$;
CREATE TABLE public.fixture_0161_midnight_cases(
  kind text,context jsonb,created_at_utc timestamptz,reference_at_utc timestamptz,
  created_document jsonb,read_document jsonb,replay_document jsonb
);
DO $ordinary_plans$
DECLARE item record; c record; created jsonb; document jsonb; replayed jsonb; result record;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('normal','UTC',timestamptz '2026-11-01 04:30Z',timestamptz '2026-11-01 04:30Z'),
    ('active','America/Havana',timestamptz '2026-10-31 12:00Z',timestamptz '2026-11-01 04:30Z'),
    ('anomalous','America/Havana',timestamptz '2026-11-01 04:30Z',timestamptz '2026-11-01 04:30Z')
  ) AS cases(kind,zone,created_at,reference_at) LOOP
    SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0161-plan-upgrade.example.test',item.kind);
    PERFORM app_data.list_personal_project_contexts('https://synthetic-0161-plan-upgrade.example.test',item.kind);
    created := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,item.zone,7,'create',item.created_at);
    IF item.kind='active' THEN
      SELECT * INTO STRICT result FROM app_data.apply_contact_submit_v3(c.app_user_id,'0162-upgrade-first-hour',1,'contact.submit.v1','0162-upgrade',
        '0162-upgrade-first-hour',0,jsonb_build_object('contactId','0162-upgrade-first-hour','workspaceId',c.workspace_id,'projectId',c.project_id,
          'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc',timestamptz '2026-11-01 04:10Z','occurredTimeZone','America/Havana',
          'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));
      IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0161 active plan contact was not accepted'; END IF;
    END IF;
    document := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,item.reference_at);
    replayed := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,item.zone,7,'create',item.reference_at);
    IF (item.kind='normal' AND (created IS NULL OR document IS NULL OR replayed IS NULL))
      OR (item.kind='active' AND ((document#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-01 05:00Z'
        OR document#>>'{progress,recorded_contact_sessions}' IS DISTINCT FROM '0'))
      OR (item.kind='anomalous' AND (created IS NOT NULL OR document IS NOT NULL OR replayed IS NOT NULL
        OR NOT EXISTS(SELECT 1 FROM app_data.personal_action_plans plan JOIN app_data.personal_action_plan_versions version USING(plan_id)
          WHERE plan.app_user_id=c.app_user_id AND version.effective_from_utc=timestamptz '2026-11-01 05:00Z'))) THEN
      RAISE EXCEPTION '0161 ordinary baseline did not retain the expected plan state for %',item.kind;
    END IF;
    INSERT INTO public.fixture_0161_midnight_cases VALUES(item.kind,to_jsonb(c),item.created_at,item.reference_at,created,document,replayed);
  END LOOP;
END
$ordinary_plans$;
CREATE TABLE public.fixture_0161_midnight_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0161_midnight_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0161_midnight_assert_upgrade() RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE saved public.fixture_0161_midnight_snapshot%ROWTYPE; item record; document jsonb; replayed jsonb; before_replay jsonb;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0161_midnight_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))<>
      (SELECT count(*)+1 FROM public.fixture_0161_midnight_catalog)
    OR EXISTS(SELECT 1 FROM public.fixture_0161_midnight_catalog old LEFT JOIN pg_proc live ON live.oid=old.oid
      WHERE CASE WHEN old.oid IN ('app_data.personal_action_plan_cycle_start(timestamptz,text,integer)'::regprocedure,
        'app_data.personal_action_plan_cycle_until(timestamptz,text)'::regprocedure)
        THEN old.catalog_row-'prosrc' IS DISTINCT FROM to_jsonb(live)-'prosrc'
        ELSE old.catalog_row IS DISTINCT FROM to_jsonb(live) END) THEN
    RAISE EXCEPTION '0161 to 0162 changed old rows, version times, or function catalog beyond the two calendar bodies';
  END IF;
  before_replay := pg_temp.fixture_database_state();
  FOR item IN TABLE public.fixture_0161_midnight_cases LOOP
    document := app_data.read_personal_action_plan((item.context->>'app_user_id')::uuid,(item.context->>'workspace_id')::uuid,
      (item.context->>'project_id')::uuid,item.reference_at_utc);
    replayed := app_data.save_personal_action_plan((item.context->>'app_user_id')::uuid,(item.context->>'workspace_id')::uuid,
      (item.context->>'project_id')::uuid,0,3,CASE WHEN item.kind='normal' THEN 'UTC' ELSE 'America/Havana' END,7,'create',item.reference_at_utc);
    IF (item.kind='normal' AND (document IS DISTINCT FROM item.read_document OR replayed IS DISTINCT FROM item.replay_document))
      OR (item.kind='active' AND (document IS NULL OR replayed IS NULL
        OR (document#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-01 04:00Z'
        OR (document#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-08 05:00Z'
        OR document#>>'{progress,recorded_contact_sessions}' IS DISTINCT FROM '1'))
      OR (item.kind='anomalous' AND (document IS NOT NULL OR replayed IS NOT NULL)) THEN
      RAISE EXCEPTION '0162 normal replay, active derived boundary, or anomalous old NULL boundary changed: %',item.kind;
    END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0162 reads or completed same-payload replays changed old plans or versions';
  END IF;
END
$function$;
