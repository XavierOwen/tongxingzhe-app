\set ON_ERROR_STOP on
\ir ../shared/database_state.sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0154_management_follow_up_consent_opt_in_precision'
  THEN RAISE EXCEPTION 'Opt-in isolation upgrade requires the real 0154 baseline'; END IF;
END
$baseline$;
CREATE TEMP TABLE fixture_0154_opt_in_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0154-opt-in-isolation.example.test/auth/v1','0154-opt-in-isolation-owner'
);
CREATE TEMP TABLE fixture_0154_opt_in_org ON COMMIT DROP AS
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://0154-opt-in-isolation.example.test/auth/v1','0154-opt-in-isolation-owner',
  '00000000-0154-4000-8000-000000000001','0154 opt-in isolation organization'
);
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '00000000-0154-4000-8000-000000000002',organization_workspace_id,'0154 opt-in isolation project'
FROM fixture_0154_opt_in_org;
CREATE TEMP TABLE fixture_0154_opt_in_assignment ON COMMIT DROP AS
SELECT assignment.* FROM fixture_0154_opt_in_org org
CROSS JOIN LATERAL app_data.assign_organization_project_member_for_identity_v1(
  'https://0154-opt-in-isolation.example.test/auth/v1','0154-opt-in-isolation-owner',
  '00000000-0154-4000-8000-000000000003',org.organization_workspace_id,
  '00000000-0154-4000-8000-000000000002',org.organization_membership_id
) assignment;
INSERT INTO app_data.management_report_capability_grants(
  capability_grant_id,project_membership_id,capability_id,active_from_utc
)
SELECT '00000000-0154-4000-8000-000000000004',project_membership_id,
  'release_management_reports',clock_timestamp()
FROM fixture_0154_opt_in_assignment;
CREATE TABLE public.fixture_0154_opt_in_receipt AS
SELECT c.app_user_id,a.project_id,'00000000-0154-4000-8000-000000000005'::uuid AS request_id,0 AS expected_version,true AS enabled,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    c.app_user_id,a.project_id,'follow_up_consent_ratio@1',
    '00000000-0154-4000-8000-000000000005',0,true
  ) AS result
FROM fixture_0154_opt_in_context c CROSS JOIN fixture_0154_opt_in_assignment a;
INSERT INTO public.fixture_0154_opt_in_receipt
SELECT app_user_id,project_id,'00000000-0154-4000-8000-000000000006',1,false,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    app_user_id,project_id,'follow_up_consent_ratio@1',
    '00000000-0154-4000-8000-000000000006',1,false
  )
FROM public.fixture_0154_opt_in_receipt;
DO $historical_receipt$
DECLARE receipt public.fixture_0154_opt_in_receipt%ROWTYPE; before_replay jsonb;
BEGIN
  IF (SELECT count(*) FROM public.fixture_0154_opt_in_receipt)<>2
    OR EXISTS (
      SELECT 1 FROM public.fixture_0154_opt_in_receipt frozen
      LEFT JOIN app_private.management_follow_up_consent_opt_in_versions version USING(request_id)
      WHERE version.requested_by_app_user_id IS DISTINCT FROM frozen.app_user_id
        OR version.project_id IS DISTINCT FROM frozen.project_id
        OR version.version_number IS DISTINCT FROM frozen.expected_version+1
        OR version.expected_version IS DISTINCT FROM frozen.expected_version
        OR version.enabled IS DISTINCT FROM frozen.enabled
        OR frozen.result IS DISTINCT FROM app_private.management_follow_up_consent_opt_in_document_v1(
          frozen.project_id,frozen.expected_version+1)
    )
  THEN RAISE EXCEPTION '0154 baseline did not seed its two normal opt-in versions and receipts'; END IF;
  before_replay := pg_temp.fixture_database_state();
  FOR receipt IN SELECT * FROM public.fixture_0154_opt_in_receipt ORDER BY expected_version LOOP
    IF app_private.configure_management_follow_up_consent_opt_in_v1(
      receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1',receipt.request_id,
      receipt.expected_version,receipt.enabled
    ) IS DISTINCT FROM receipt.result
    THEN RAISE EXCEPTION '0154 historical opt-in replay changed its receipt'; END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay
  THEN RAISE EXCEPTION '0154 historical opt-in replay changed business facts'; END IF;
END
$historical_receipt$;
CREATE TABLE public.fixture_0154_opt_in_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0154_opt_in_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0154_opt_in_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0154_opt_in_snapshot%ROWTYPE;
  receipt public.fixture_0154_opt_in_receipt%ROWTYPE;
  replayed jsonb;
  original_source text;
  actual_source text;
  configure_oid oid := 'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'::regprocedure;
  anchor text := $anchor$  -- The resolver takes the organization, project-membership and capability$anchor$;
  isolation_guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'management follow-up consent opt-in requires read committed';
  END IF;

$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0154_opt_in_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0155 opt-in isolation verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0154_opt_in_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=configure_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0154→0155 changed business facts or function metadata beyond the configure body'; END IF;
  SELECT catalog_row->>'prosrc' INTO STRICT original_source
  FROM public.fixture_0154_opt_in_catalog WHERE oid=configure_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=configure_oid;
  IF length(original_source)-length(replace(original_source,anchor,''))<>length(anchor)
    OR strpos(original_source,isolation_guard)<>0
    OR actual_source IS DISTINCT FROM replace(original_source,anchor,isolation_guard||anchor)
  THEN RAISE EXCEPTION '0154→0155 changed configure beyond its exact isolation guard'; END IF;
  FOR receipt IN SELECT * FROM public.fixture_0154_opt_in_receipt ORDER BY expected_version LOOP
    replayed := app_private.configure_management_follow_up_consent_opt_in_v1(
      receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1',receipt.request_id,
      receipt.expected_version,receipt.enabled
    );
    IF replayed IS DISTINCT FROM receipt.result
      OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    THEN RAISE EXCEPTION '0155 exact opt-in replay changed a historical receipt or business facts'; END IF;
  END LOOP;
END
$function$;
