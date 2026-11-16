\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) IS DISTINCT FROM '0162_personal_action_plan_midnight_fold' THEN
    RAISE EXCEPTION 'personal plan skipped-date upgrade requires the real 0162 baseline';
  END IF;
END
$baseline$;
CREATE TABLE public.fixture_0162_skipped_cases(kind text,context jsonb,zone text,weekday integer,reference_at_utc timestamptz,read_document jsonb,replay_document jsonb);
DO $ordinary_plans$
DECLARE item record; c record; initial jsonb; scheduled jsonb; document jsonb; replayed jsonb; reference_at timestamptz := timestamptz '2011-12-31 00:00Z';
BEGIN
  FOR item IN SELECT * FROM (VALUES ('affected','Pacific/Apia',5,timestamptz '2012-01-06 10:00Z'),
    ('saturday','Pacific/Apia',6,timestamptz '2012-01-06 10:00Z'),('normal','UTC',5,timestamptz '2012-01-06 00:00Z')) AS cases(kind,zone,weekday,old_until) LOOP
    SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0162-skipped-upgrade.example.test',item.kind);
    PERFORM app_data.list_personal_project_contexts('https://synthetic-0162-skipped-upgrade.example.test',item.kind);
    initial := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,item.zone,item.weekday,'create',reference_at);
    scheduled := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,4,item.zone,item.weekday,'change',reference_at+interval '1 hour');
    document := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,reference_at);
    replayed := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,4,item.zone,item.weekday,'change',reference_at+interval '1 hour');
    IF initial IS NULL OR document IS NULL OR replayed IS NULL
      OR (initial#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM item.old_until
      OR (scheduled#>>'{pending,effective_from_utc}')::timestamptz IS DISTINCT FROM item.old_until THEN
      RAISE EXCEPTION '0162 ordinary skipped-date baseline differs for %',item.kind;
    END IF;
    INSERT INTO public.fixture_0162_skipped_cases VALUES(item.kind,to_jsonb(c),item.zone,item.weekday,reference_at,document,replayed);
  END LOOP;
END
$ordinary_plans$;
CREATE TABLE public.fixture_0162_skipped_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_proc procedure WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0162_skipped_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0162_skipped_assert_upgrade() RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE saved public.fixture_0162_skipped_snapshot%ROWTYPE; item record; document jsonb; replayed jsonb; later jsonb; expected_read jsonb; expected_replay jsonb; before_replay jsonb;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0162_skipped_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))<>
      (SELECT count(*)+1 FROM public.fixture_0162_skipped_catalog)
    OR EXISTS(SELECT 1 FROM public.fixture_0162_skipped_catalog old LEFT JOIN pg_proc live ON live.oid=old.oid
      WHERE CASE WHEN old.oid IN ('app_data.personal_action_plan_document(uuid,timestamptz)'::regprocedure,
        'app_data.save_personal_action_plan(uuid,uuid,uuid,integer,integer,text,integer,text,timestamptz)'::regprocedure)
        THEN old.catalog_row-'prosrc' IS DISTINCT FROM to_jsonb(live)-'prosrc'
        ELSE old.catalog_row IS DISTINCT FROM to_jsonb(live) END) THEN
    RAISE EXCEPTION '0162 to 0163 changed old rows, pending version times, or catalog beyond document/save bodies';
  END IF;
  before_replay := pg_temp.fixture_database_state();
  FOR item IN TABLE public.fixture_0162_skipped_cases LOOP
    document := app_data.read_personal_action_plan((item.context->>'app_user_id')::uuid,(item.context->>'workspace_id')::uuid,
      (item.context->>'project_id')::uuid,item.reference_at_utc);
    replayed := app_data.save_personal_action_plan((item.context->>'app_user_id')::uuid,(item.context->>'workspace_id')::uuid,
      (item.context->>'project_id')::uuid,1,4,item.zone,item.weekday,'change',item.reference_at_utc+interval '1 hour');
    expected_read := item.read_document; expected_replay := item.replay_document;
    IF item.kind='affected' THEN
      expected_read := jsonb_set(expected_read,'{progress,cycle_until_utc}',to_jsonb(timestamptz '2012-01-05 10:00Z'));
      expected_replay := jsonb_set(expected_replay,'{progress,cycle_until_utc}',to_jsonb(timestamptz '2012-01-05 10:00Z'));
      later := app_data.read_personal_action_plan((item.context->>'app_user_id')::uuid,(item.context->>'workspace_id')::uuid,
        (item.context->>'project_id')::uuid,timestamptz '2012-01-05 12:00Z');
      IF later#>>'{current,weekly_contact_target}' IS DISTINCT FROM '3'
        OR (later#>>'{pending,effective_from_utc}')::timestamptz IS DISTINCT FROM timestamptz '2012-01-06 10:00Z' THEN
        RAISE EXCEPTION '0163 rewrote the old late pending version instead of preserving its compatibility boundary';
      END IF;
    END IF;
    IF document IS DISTINCT FROM expected_read OR replayed IS DISTINCT FROM expected_replay THEN
      RAISE EXCEPTION '0163 changed the original replay or more than the affected derived until: %',item.kind;
    END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0163 original read/replay changed plans or appended versions';
  END IF;
END
$function$;
