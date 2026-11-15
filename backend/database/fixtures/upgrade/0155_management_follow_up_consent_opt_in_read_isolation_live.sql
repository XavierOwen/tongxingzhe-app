\set ON_ERROR_STOP on
\ir ../shared/database_state.sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0155_management_follow_up_consent_opt_in_isolation'
  THEN RAISE EXCEPTION 'Opt-in read isolation upgrade requires the real 0155 baseline'; END IF;
END
$baseline$;
CREATE TEMP TABLE fixture_0155_opt_in_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0155-opt-in-read-isolation.example.test/auth/v1','0155-opt-in-read-isolation-owner'
);
CREATE TEMP TABLE fixture_0155_opt_in_org ON COMMIT DROP AS
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://0155-opt-in-read-isolation.example.test/auth/v1','0155-opt-in-read-isolation-owner',
  '00000000-0155-4000-8000-000000000001','0155 opt-in read isolation organization'
);
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '00000000-0155-4000-8000-000000000002',organization_workspace_id,'0155 opt-in read isolation project'
FROM fixture_0155_opt_in_org;
CREATE TEMP TABLE fixture_0155_opt_in_assignment ON COMMIT DROP AS
SELECT assignment.* FROM fixture_0155_opt_in_org org
CROSS JOIN LATERAL app_data.assign_organization_project_member_for_identity_v1(
  'https://0155-opt-in-read-isolation.example.test/auth/v1','0155-opt-in-read-isolation-owner',
  '00000000-0155-4000-8000-000000000003',org.organization_workspace_id,
  '00000000-0155-4000-8000-000000000002',org.organization_membership_id
) assignment;
INSERT INTO app_data.management_report_capability_grants(
  capability_grant_id,project_membership_id,capability_id,active_from_utc
)
SELECT '00000000-0155-4000-8000-000000000004',project_membership_id,
  'release_management_reports',clock_timestamp()
FROM fixture_0155_opt_in_assignment;
CREATE TABLE public.fixture_0155_opt_in_receipt AS
SELECT c.app_user_id,a.project_id,'00000000-0155-4000-8000-000000000005'::uuid AS request_id,0 AS expected_version,true AS enabled,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    c.app_user_id,a.project_id,'follow_up_consent_ratio@1',
    '00000000-0155-4000-8000-000000000005',0,true
  ) AS result
FROM fixture_0155_opt_in_context c CROSS JOIN fixture_0155_opt_in_assignment a;
INSERT INTO public.fixture_0155_opt_in_receipt
SELECT app_user_id,project_id,'00000000-0155-4000-8000-000000000006',1,false,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    app_user_id,project_id,'follow_up_consent_ratio@1',
    '00000000-0155-4000-8000-000000000006',1,false
  )
FROM public.fixture_0155_opt_in_receipt;
DO $historical_receipt$
DECLARE receipt public.fixture_0155_opt_in_receipt%ROWTYPE; before_replay jsonb;
BEGIN
  IF (SELECT count(*) FROM public.fixture_0155_opt_in_receipt)<>2
    OR EXISTS (
      SELECT 1 FROM public.fixture_0155_opt_in_receipt frozen
      LEFT JOIN app_private.management_follow_up_consent_opt_in_versions version USING(request_id)
      WHERE version.requested_by_app_user_id IS DISTINCT FROM frozen.app_user_id
        OR version.project_id IS DISTINCT FROM frozen.project_id
        OR version.version_number IS DISTINCT FROM frozen.expected_version+1
        OR version.expected_version IS DISTINCT FROM frozen.expected_version
        OR version.enabled IS DISTINCT FROM frozen.enabled
        OR frozen.result IS DISTINCT FROM app_private.management_follow_up_consent_opt_in_document_v1(
          frozen.project_id,frozen.expected_version+1)
    )
  THEN RAISE EXCEPTION '0155 baseline did not seed its two normal opt-in versions and receipts'; END IF;
  before_replay := pg_temp.fixture_database_state();
  FOR receipt IN SELECT * FROM public.fixture_0155_opt_in_receipt ORDER BY expected_version LOOP
    IF app_private.configure_management_follow_up_consent_opt_in_v1(
      receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1',receipt.request_id,
      receipt.expected_version,receipt.enabled
    ) IS DISTINCT FROM receipt.result
    THEN RAISE EXCEPTION '0155 historical opt-in replay changed its receipt'; END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay
  THEN RAISE EXCEPTION '0155 historical opt-in replay changed business facts'; END IF;
END
$historical_receipt$;
CREATE TABLE public.fixture_0155_opt_in_read_document AS
SELECT receipt.app_user_id,receipt.project_id,
  app_private.read_management_follow_up_consent_opt_in_v1(
    receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1'
  ) AS result,
  app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
    receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1'
  ) AS bridge_result
FROM public.fixture_0155_opt_in_receipt receipt WHERE expected_version=1;
DO $historical_read$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.fixture_0155_opt_in_read_document document
    JOIN public.fixture_0155_opt_in_receipt receipt USING(app_user_id,project_id)
    WHERE receipt.expected_version=1 AND document.result=document.bridge_result
      AND document.result->>'status'='not_enabled'
      AND document.result->'configuration'=receipt.result
  ) THEN RAISE EXCEPTION '0155 baseline did not preserve its normal reader and candidate bridge documents'; END IF;
END
$historical_read$;
CREATE TABLE public.fixture_0155_opt_in_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0155_opt_in_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0155_opt_in_read_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0155_opt_in_snapshot%ROWTYPE;
  receipt public.fixture_0155_opt_in_receipt%ROWTYPE;
  replayed jsonb;
  document public.fixture_0155_opt_in_read_document%ROWTYPE;
  original_source text;
  actual_source text;
  reader_oid oid := 'app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)'::regprocedure;
  prelude text := $prelude$      MESSAGE = 'invalid management follow-up consent opt-in read';
  END IF;

$prelude$;
  isolation_guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'management follow-up consent opt-in read requires read committed';
  END IF;

$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0155_opt_in_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0156 opt-in read isolation verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0155_opt_in_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=reader_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0155→0156 changed business facts or function metadata beyond the reader body'; END IF;
  SELECT catalog_row->>'prosrc' INTO STRICT original_source
  FROM public.fixture_0155_opt_in_catalog WHERE oid=reader_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=reader_oid;
  IF length(original_source)-length(replace(original_source,prelude,''))<>length(prelude)
    OR strpos(original_source,isolation_guard)<>0
    OR actual_source IS DISTINCT FROM replace(original_source,prelude,prelude||isolation_guard)
  THEN RAISE EXCEPTION '0155→0156 changed reader beyond its exact isolation guard'; END IF;
  SELECT * INTO STRICT document FROM public.fixture_0155_opt_in_read_document;
  IF app_private.read_management_follow_up_consent_opt_in_v1(
      document.app_user_id,document.project_id,'follow_up_consent_ratio@1'
    ) IS DISTINCT FROM document.result
    OR app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
      document.app_user_id,document.project_id,'follow_up_consent_ratio@1'
    ) IS DISTINCT FROM document.bridge_result
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0156 reader or candidate bridge changed the original document or business facts'; END IF;
  FOR receipt IN SELECT * FROM public.fixture_0155_opt_in_receipt ORDER BY expected_version LOOP
    replayed := app_private.configure_management_follow_up_consent_opt_in_v1(
      receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1',receipt.request_id,
      receipt.expected_version,receipt.enabled
    );
    IF replayed IS DISTINCT FROM receipt.result
      OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    THEN RAISE EXCEPTION '0156 exact opt-in replay changed a historical receipt or business facts'; END IF;
  END LOOP;
END
$function$;
