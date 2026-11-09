\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0146_personal_target_merge_activation_isolation'
  THEN RAISE EXCEPTION 'Assignment end isolation upgrade requires the real 0146 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0146_assignment_end_context ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
  '7f478000-0000-4000-8000-000000000001'::uuid AS target_id,
  '7f478000-0000-4000-8000-000000000011'::uuid AS assignment_id
FROM app_data.bootstrap_personal_context('https://0146-upgrade-assignment-end-isolation.example.test','owner') c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0146-upgrade-assignment-end-isolation.example.test','owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT target_id,workspace_id,'person','0146 upgrade original target','+1 773 555 0147','0146@example.test',app_user_id
FROM fixture_0146_assignment_end_context;

INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT assignment_id,target_id,app_user_id,app_user_id
FROM fixture_0146_assignment_end_context;

CREATE TABLE public.fixture_0146_assignment_end_isolation_receipt AS
SELECT c.*,
  app_data.end_personal_target_assignment_v1(c.app_user_id,c.workspace_id,c.project_id,c.assignment_id) AS ended_at_utc
FROM fixture_0146_assignment_end_context c;

DO $receipt$
DECLARE
  receipt public.fixture_0146_assignment_end_isolation_receipt%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM public.fixture_0146_assignment_end_isolation_receipt;
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_assignment_end_events_v1 e
    JOIN app_data.promotion_target_assignments a USING (assignment_id)
    JOIN app_data.promotion_targets t USING (promotion_target_id,workspace_id)
    WHERE e.assignment_id=receipt.assignment_id AND e.actor_app_user_id=receipt.app_user_id
      AND e.workspace_id=receipt.workspace_id AND e.project_id=receipt.project_id
      AND e.reason='user_requested' AND e.ended_at_utc=receipt.ended_at_utc
      AND a.app_user_id=receipt.app_user_id AND a.end_reason=e.reason AND a.ended_at=e.ended_at_utc
      AND t.promotion_target_id=receipt.target_id AND t.status='active' AND t.target_type='person'
      AND t.display_name='0146 upgrade original target' AND t.phone='+1 773 555 0147' AND t.email='0146@example.test'
      AND t.created_by_app_user_id=receipt.app_user_id
  ) THEN RAISE EXCEPTION '0146 upgrade did not end the original assignment with one correct event and its target still active'; END IF;
END
$receipt$;

CREATE TABLE public.fixture_0146_assignment_end_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);

CREATE TABLE public.fixture_0146_assignment_end_isolation_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0146_assignment_end_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0146_assignment_end_isolation_snapshot%ROWTYPE;
  receipt public.fixture_0146_assignment_end_isolation_receipt%ROWTYPE;
  assignment_end_oid oid := 'app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  old_source text;
  actual_source text;
  authorization_start integer;
  guard CONSTANT text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target assignment end requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0146_assignment_end_isolation_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0147 assignment end replay verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0147_personal_target_assignment_end_isolation'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0146_assignment_end_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=assignment_end_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0146→0147 changed legacy data or function catalog'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_source
  FROM public.fixture_0146_assignment_end_isolation_catalog WHERE oid=assignment_end_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=assignment_end_oid;
  authorization_start := strpos(old_source,'  IF NOT app_data.promotion_target_context_authorized(');
  IF authorization_start=0 OR strpos(old_source,guard)<>0
    OR actual_source IS DISTINCT FROM overlay(old_source PLACING guard FROM authorization_start FOR 0)
  THEN RAISE EXCEPTION '0146→0147 changed assignment end beyond the exact three-line guard before first authorization'; END IF;

  SELECT * INTO STRICT receipt FROM public.fixture_0146_assignment_end_isolation_receipt;
  IF app_data.end_personal_target_assignment_v1(
    receipt.app_user_id,receipt.workspace_id,receipt.project_id,receipt.assignment_id
  ) IS DISTINCT FROM receipt.ended_at_utc
  THEN RAISE EXCEPTION '0147 RC assignment end replay changed its original receipt'; END IF;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0147 RC assignment end replay changed business data'; END IF;
END
$function$;
