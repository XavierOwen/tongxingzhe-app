\set ON_ERROR_STOP on
\set fixture_0164_definitions_only true
\ir ../0164_management_report_frozen_periods.sql
\unset fixture_0164_definitions_only

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) IS DISTINCT FROM '0163_personal_action_plan_skipped_date' THEN
    RAISE EXCEPTION 'frozen report periods upgrade requires the real 0163 baseline';
  END IF;
END
$baseline$;
CREATE TABLE public.fixture_0163_frozen_reports(context jsonb,reports jsonb);
DO $normal_publication$
DECLARE c jsonb; reports jsonb;
BEGIN
  c:=pg_temp.fixture_0164_seed('upgrade');
  reports:=pg_temp.fixture_0164_publish(c);
  PERFORM pg_temp.fixture_0164_read_replay(c,reports);
  INSERT INTO public.fixture_0163_frozen_reports VALUES(c,reports);
END
$normal_publication$;
CREATE TABLE public.fixture_0163_frozen_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_proc procedure WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0163_frozen_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0163_frozen_assert_restored_calendar() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE item record; saved_report jsonb; family record; current_periods jsonb; differs boolean; detail jsonb; replayed jsonb;
  attempt integer; actual_state text; before_state jsonb:=pg_temp.fixture_database_state(); audit_keys text[]:=ARRAY[
    'app_private.management_interest_report_snapshot_access_events','app_private.management_current_city_report_snapshot_access_events',
    'app_private.management_follow_up_consent_report_snapshot_access_events','app_private.management_original_region_report_snapshot_access_events'];
BEGIN
  FOR item IN TABLE public.fixture_0163_frozen_reports LOOP
    FOR saved_report IN SELECT value FROM jsonb_array_elements(item.reports) LOOP
      SELECT * INTO STRICT family FROM pg_temp.fixture_0164_families() WHERE fixture_0164_families.family=saved_report->>'family';
      current_periods:=app_private.resolve_management_report_periods_v1(saved_report#>>'{report,periods,reporting_time_zone}',
        (saved_report#>>'{report,periods,data_cutoff_utc}')::timestamptz);
      differs:=current_periods IS DISTINCT FROM saved_report#>'{report,periods}';
      FOR attempt IN 1..2 LOOP
        actual_state:=NULL; detail:=NULL;
        BEGIN
          EXECUTE format('SELECT app_private.%I($1,$2,$3)',family.reader)
            INTO detail USING (item.context->>'actor')::uuid,(item.context->>'project')::uuid,(saved_report->>'snapshot')::uuid;
        EXCEPTION WHEN invalid_parameter_value THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
        RAISE NOTICE '0164 restored family=% changed_periods=% attempt=% status=% SQLSTATE=%',family.family,differs,attempt,detail->>'result_status',actual_state;
        IF differs AND family.family='current_city' THEN
          IF actual_state IS DISTINCT FROM '22023' THEN RAISE EXCEPTION '0164 restored old current-city validator no longer shows the period mismatch'; END IF;
        ELSIF actual_state IS NOT NULL OR detail->>'result_status' IS DISTINCT FROM (CASE WHEN differs THEN 'untrusted_provenance' ELSE 'completed' END)
          OR (NOT differs AND detail->'protected_report' IS DISTINCT FROM saved_report->'report') THEN
          RAISE EXCEPTION '0164 restored old read differs from its resolver comparison: %, %',family.family,detail;
        END IF;
        EXECUTE format('SELECT app_private.%I($1,$2,$3,$4,1)',family.releaser)
          INTO replayed USING (saved_report->>'request')::uuid,(item.context->>'actor')::uuid,(item.context->>'project')::uuid,family.report_id;
        IF replayed IS DISTINCT FROM saved_report->'receipt' THEN RAISE EXCEPTION '0164 restored old exact release replay changed: %',family.family; END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  IF before_state-audit_keys IS DISTINCT FROM pg_temp.fixture_database_state()-audit_keys THEN
    RAISE EXCEPTION '0164 restored pre-upgrade read/replay changed release facts or frozen documents';
  END IF;
END
$function$;

CREATE FUNCTION public.fixture_0163_frozen_capture_restored_catalog() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0163_frozen_snapshot%ROWTYPE;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0163_frozen_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state THEN
    RAISE EXCEPTION '0164 restore changed old business rows or migrations before SQL upgrade';
  END IF;
  -- Restore can assign different OIDs; capture the current SQL-0163 catalog only after row fidelity is established.
  TRUNCATE public.fixture_0163_frozen_catalog;
  INSERT INTO public.fixture_0163_frozen_catalog SELECT oid,to_jsonb(procedure) FROM pg_proc procedure
    WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
END
$function$;

CREATE FUNCTION public.fixture_0163_frozen_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0163_frozen_snapshot%ROWTYPE; item record;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0163_frozen_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))<>
      (SELECT count(*) FROM public.fixture_0163_frozen_catalog)
    OR EXISTS(SELECT 1 FROM public.fixture_0163_frozen_catalog old LEFT JOIN pg_proc live ON live.oid=old.oid
      WHERE CASE WHEN old.oid IN ('app_private.validate_management_interest_report_document_v1(jsonb)'::regprocedure,
        'app_private.validate_management_current_city_report_document_v1(jsonb)'::regprocedure,
        'app_private.validate_management_original_region_report_document_v1(jsonb)'::regprocedure,
        'app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)'::regprocedure)
        THEN old.catalog_row-'prosrc' IS DISTINCT FROM to_jsonb(live)-'prosrc'
        ELSE old.catalog_row IS DISTINCT FROM to_jsonb(live) END) THEN
    RAISE EXCEPTION '0163 to 0164 changed old snapshots, receipts, timezone versions, requests, or catalog beyond four validator bodies';
  END IF;
  FOR item IN TABLE public.fixture_0163_frozen_reports LOOP
    PERFORM pg_temp.fixture_0164_read_replay(item.context,item.reports);
  END LOOP;
END
$function$;
