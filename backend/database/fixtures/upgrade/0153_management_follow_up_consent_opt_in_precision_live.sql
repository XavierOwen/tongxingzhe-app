\set ON_ERROR_STOP on
\ir ../shared/database_state.sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0153_promotion_target_retention_calendar'
  THEN RAISE EXCEPTION 'Opt-in precision upgrade requires the real 0153 baseline'; END IF;
END
$baseline$;
CREATE TEMP TABLE fixture_0153_opt_in_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0153-opt-in-precision.example.test/auth/v1','0153-opt-in-precision-owner'
);
CREATE TEMP TABLE fixture_0153_opt_in_org ON COMMIT DROP AS
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://0153-opt-in-precision.example.test/auth/v1','0153-opt-in-precision-owner',
  '00000000-0153-4000-8000-000000000001','0153 opt-in precision organization'
);
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '00000000-0153-4000-8000-000000000002',organization_workspace_id,'0153 opt-in precision project'
FROM fixture_0153_opt_in_org;
CREATE TEMP TABLE fixture_0153_opt_in_assignment ON COMMIT DROP AS
SELECT assignment.* FROM fixture_0153_opt_in_org org
CROSS JOIN LATERAL app_data.assign_organization_project_member_for_identity_v1(
  'https://0153-opt-in-precision.example.test/auth/v1','0153-opt-in-precision-owner',
  '00000000-0153-4000-8000-000000000003',org.organization_workspace_id,
  '00000000-0153-4000-8000-000000000002',org.organization_membership_id
) assignment;
INSERT INTO app_data.management_report_capability_grants(
  capability_grant_id,project_membership_id,capability_id,active_from_utc
)
SELECT '00000000-0153-4000-8000-000000000004',project_membership_id,
  'release_management_reports',date_trunc('milliseconds',clock_timestamp())+interval '1 millisecond 1 microsecond'
FROM fixture_0153_opt_in_assignment;
-- Let the legitimate grant predate the resolver's millisecond timestamp on 0153.
SELECT pg_sleep(0.01);
CREATE TABLE public.fixture_0153_opt_in_receipt AS
SELECT c.app_user_id,a.project_id,'00000000-0153-4000-8000-000000000005'::uuid AS request_id,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    c.app_user_id,a.project_id,'follow_up_consent_ratio@1',
    '00000000-0153-4000-8000-000000000005',0,true
  ) AS result
FROM fixture_0153_opt_in_context c CROSS JOIN fixture_0153_opt_in_assignment a;
DO $historical_receipt$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0153_opt_in_receipt)<>1
    OR NOT EXISTS (
      SELECT 1 FROM public.fixture_0153_opt_in_receipt receipt
      JOIN app_private.management_follow_up_consent_opt_in_versions version USING(request_id)
      JOIN app_data.management_report_capability_grants capability USING(capability_grant_id)
      WHERE version.version_number=1 AND version.expected_version=0 AND version.enabled
        AND version.requested_by_app_user_id=receipt.app_user_id
        AND version.project_id=receipt.project_id
        AND version.authorization_reference_at_utc>=capability.active_from_utc
        AND capability.active_from_utc-date_trunc('milliseconds',capability.active_from_utc)=interval '1 microsecond'
        AND receipt.result=app_private.management_follow_up_consent_opt_in_document_v1(receipt.project_id,1)
    )
  THEN RAISE EXCEPTION '0153 baseline did not seed its normal opt-in version and receipt'; END IF;
END
$historical_receipt$;
CREATE TABLE public.fixture_0153_opt_in_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0153_opt_in_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0153_opt_in_precision_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0153_opt_in_snapshot%ROWTYPE;
  receipt public.fixture_0153_opt_in_receipt%ROWTYPE;
  replayed jsonb;
  original_source text;
  actual_source text;
  configure_oid oid := 'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'::regprocedure;
  old_expression text := $old$authorization_reference_at_utc :=
    (authorization_evidence->>'reference_at_utc')::timestamptz;$old$;
  new_expression text := $new$authorization_reference_at_utc :=
    pg_catalog.clock_timestamp();$new$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0153_opt_in_snapshot;
  SELECT * INTO STRICT receipt FROM public.fixture_0153_opt_in_receipt;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0154 opt-in precision verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0153_opt_in_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=configure_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0153→0154 changed business facts or function metadata beyond the configure body'; END IF;
  SELECT catalog_row->>'prosrc' INTO STRICT original_source
  FROM public.fixture_0153_opt_in_catalog WHERE oid=configure_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=configure_oid;
  IF length(original_source)-length(replace(original_source,old_expression,''))<>length(old_expression)
    OR strpos(original_source,new_expression)<>0
    OR actual_source IS DISTINCT FROM replace(original_source,old_expression,new_expression)
  THEN RAISE EXCEPTION '0153→0154 changed configure beyond its exact authorization timestamp expression'; END IF;
  replayed := app_private.configure_management_follow_up_consent_opt_in_v1(
    receipt.app_user_id,receipt.project_id,'follow_up_consent_ratio@1',receipt.request_id,0,true
  );
  IF replayed IS DISTINCT FROM receipt.result
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0154 exact opt-in replay changed the historical receipt or business facts'; END IF;
END
$function$;
