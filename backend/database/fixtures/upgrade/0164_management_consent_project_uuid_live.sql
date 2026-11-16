\set ON_ERROR_STOP on
\set fixture_0165_definitions_only true
\ir ../0165_management_consent_project_uuid.sql
\unset fixture_0165_definitions_only

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) IS DISTINCT FROM '0164_management_report_frozen_periods' THEN
    RAISE EXCEPTION 'consent project UUID upgrade requires the real 0164 baseline';
  END IF;
END
$baseline$;
CREATE TABLE public.fixture_0164_consent_uuid_cases(kind text,context jsonb,report jsonb,producer_document jsonb);
DO $normal_projects$
DECLARE original_context jsonb; pending_context jsonb; report jsonb; document jsonb; before_errors jsonb; actual_state text;
BEGIN
  original_context:=pg_temp.fixture_0164_seed('0165-upgrade');
  report:=pg_temp.fixture_0165_publish(original_context);
  PERFORM pg_temp.fixture_0164_read_replay(original_context,jsonb_build_array(report));
  INSERT INTO public.fixture_0164_consent_uuid_cases VALUES('completed',original_context,report,NULL);
  pending_context:=pg_temp.fixture_0165_project(original_context,'8abc');
  document:=app_private.execute_management_follow_up_consent_ratio_report_v1((pending_context->>'actor')::uuid,
    (pending_context->>'project')::uuid,pending_context->>'zone',clock_timestamp());
  IF document->>'status' IS DISTINCT FROM 'completed' THEN RAISE EXCEPTION '0164 canonical 8abc project did not produce its normal document'; END IF;
  before_errors:=pg_temp.fixture_database_state(); actual_state:=NULL;
  BEGIN PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(document);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '22023' OR pg_temp.fixture_database_state() IS DISTINCT FROM before_errors THEN
    RAISE EXCEPTION '0164 old canonical UUID validator did not reject with zero fact changes: %',actual_state;
  END IF;
  actual_state:=NULL;
  BEGIN PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(gen_random_uuid(),(pending_context->>'actor')::uuid,
    (pending_context->>'project')::uuid,'contact_target_follow_up_consent_ratio_two_periods',1);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '22023' OR pg_temp.fixture_database_state() IS DISTINCT FROM before_errors THEN
    RAISE EXCEPTION '0164 old canonical UUID release did not reject with zero release facts: %',actual_state;
  END IF;
  INSERT INTO public.fixture_0164_consent_uuid_cases VALUES('pending',pending_context,NULL,document);
END
$normal_projects$;
CREATE TABLE public.fixture_0164_consent_uuid_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_proc procedure WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0164_consent_uuid_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0164_consent_uuid_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0164_consent_uuid_snapshot%ROWTYPE; item record; published jsonb; after_publication jsonb; relation record;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0164_consent_uuid_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))<>
      (SELECT count(*) FROM public.fixture_0164_consent_uuid_catalog)
    OR EXISTS(SELECT 1 FROM public.fixture_0164_consent_uuid_catalog old LEFT JOIN pg_proc live ON live.oid=old.oid
      WHERE CASE WHEN old.oid='app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)'::regprocedure
        THEN old.catalog_row-'prosrc' IS DISTINCT FROM to_jsonb(live)-'prosrc'
          OR replace(old.catalog_row->>'prosrc','[89ab][0-9]{3}','[89ab][0-9a-f]{3}') IS DISTINCT FROM live.prosrc
        ELSE old.catalog_row IS DISTINCT FROM to_jsonb(live) END) THEN
    RAISE EXCEPTION '0164 to 0165 changed old facts, function identities, or more than the single UUID character class';
  END IF;
  FOR item IN TABLE public.fixture_0164_consent_uuid_cases LOOP
    IF item.kind='completed' THEN
      PERFORM pg_temp.fixture_0164_read_replay(item.context,jsonb_build_array(item.report));
    ELSE
      PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(item.producer_document);
      published:=pg_temp.fixture_0165_publish(item.context);
      PERFORM pg_temp.fixture_0164_read_replay(item.context,jsonb_build_array(published));
    END IF;
  END LOOP;
  after_publication:=pg_temp.fixture_database_state();
  FOR relation IN SELECT key,value FROM jsonb_each(saved.business_state) LOOP
    IF NOT relation.value<@(after_publication->relation.key) THEN
      RAISE EXCEPTION '0165 new canonical project publication changed an old source or receipt row in %',relation.key;
    END IF;
  END LOOP;
END
$function$;
