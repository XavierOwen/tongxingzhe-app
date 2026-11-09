\set ON_ERROR_STOP on
\ir ../shared/database_state.sql

BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0147_personal_target_assignment_end_isolation'
  THEN RAISE EXCEPTION 'Legacy activation isolation upgrade requires the real 0147 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0147_legacy_activation_context ON COMMIT DROP AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
  '7f488000-0000-4000-8000-000000000001'::uuid AS first_target,
  '7f488000-0000-4000-8000-000000000002'::uuid AS second_target
FROM app_data.bootstrap_personal_context('https://0147-upgrade-legacy-activation.example.test','owner') c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0147-upgrade-legacy-activation.example.test','owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0147 upgrade original target','+1 773 555 0148','0147@example.test',c.app_user_id
FROM fixture_0147_legacy_activation_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.target_id,t.target_id,c.app_user_id,c.app_user_id
FROM fixture_0147_legacy_activation_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

CREATE TEMP TABLE fixture_0147_legacy_activation_result ON COMMIT DROP AS
SELECT c.*,preview.preview_id,
  app_private.activate_personal_target_merge_generation_v1(c.app_user_id,c.project_id,preview.preview_id) AS generation_id
FROM fixture_0147_legacy_activation_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0147-upgrade-legacy-activation.example.test','owner',c.project_id,c.first_target,c.second_target
) preview;

DO $activation$
DECLARE
  activated fixture_0147_legacy_activation_result%ROWTYPE;
BEGIN
  SELECT * INTO STRICT activated FROM fixture_0147_legacy_activation_result;
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_generations_v1 g
    JOIN app_private.personal_target_pair_preview_receipts r USING (workspace_id)
    WHERE g.generation_id=activated.generation_id AND g.created_by_app_user_id=activated.app_user_id
      AND g.workspace_id=activated.workspace_id AND g.target_type='person'
      AND r.preview_id=activated.preview_id AND r.actor_app_user_id=activated.app_user_id
      AND r.first_target_id=activated.first_target AND r.second_target_id=activated.second_target
      AND r.first_assignment_id=activated.first_target AND r.second_assignment_id=activated.second_target
  ) OR (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id)
    FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id=activated.generation_id)
    IS DISTINCT FROM ARRAY[activated.first_target,activated.second_target]
    OR (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id)
    FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=activated.generation_id)
    IS DISTINCT FROM ARRAY[activated.first_target,activated.second_target]
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1
      WHERE generation_id=activated.generation_id)
  THEN RAISE EXCEPTION '0147 upgrade did not create the original legacy generation, both members and its preview receipt'; END IF;
END
$activation$;

CREATE TABLE public.fixture_0147_legacy_activation_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);

CREATE TABLE public.fixture_0147_legacy_activation_isolation_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0147_legacy_activation_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0147_legacy_activation_isolation_snapshot%ROWTYPE;
  activation_oid oid := 'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'::regprocedure;
  old_source text;
  actual_source text;
  begin_marker CONSTANT text := E'\nBEGIN\n';
  begin_position integer;
  guard CONSTANT text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'legacy personal target merge generation activation requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0147_legacy_activation_isolation_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0148 legacy activation upgrade verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0148_personal_target_merge_legacy_activation_isolation'
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0147_legacy_activation_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=activation_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0147→0148 changed legacy data or function catalog'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_source
  FROM public.fixture_0147_legacy_activation_isolation_catalog WHERE oid=activation_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=activation_oid;
  begin_position := strpos(old_source,begin_marker);
  IF begin_position=0 OR strpos(old_source,guard)<>0
    OR actual_source IS DISTINCT FROM overlay(old_source PLACING guard FROM begin_position+length(begin_marker) FOR 0)
  THEN RAISE EXCEPTION '0147→0148 changed legacy activation beyond the exact three-line guard after BEGIN'; END IF;
END
$function$;
