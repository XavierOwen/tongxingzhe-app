\set ON_ERROR_STOP on
\ir ../shared/database_state.sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0152_personal_target_audited_merge_metadata_isolation'
  THEN RAISE EXCEPTION 'Retention calendar upgrade requires the real 0152 baseline'; END IF;
END
$baseline$;
CREATE TEMP TABLE fixture_0152_calendar_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0152-retention-calendar.example.test/auth/v1','0152-retention-calendar-owner'
);
CREATE TEMP TABLE fixture_0152_calendar_target ON COMMIT DROP AS
SELECT (created.target->>'target_id')::uuid AS target_id
FROM fixture_0152_calendar_context c
CROSS JOIN LATERAL app_data.create_promotion_target(
  c.app_user_id,c.workspace_id,c.project_id,'person','0152 historical retention receipt',
  NULL,NULL,'0152-calendar-target'
) created;
SELECT app_data.configure_promotion_target_retention_policy(c.app_user_id,c.workspace_id,c.project_id,6)
FROM fixture_0152_calendar_context c;
SET LOCAL timezone='America/New_York';
CREATE TABLE public.fixture_0152_calendar_receipt AS
SELECT c.app_user_id,c.workspace_id,c.project_id,t.target_id,action.result
FROM fixture_0152_calendar_context c CROSS JOIN fixture_0152_calendar_target t
CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,'renew','purpose_confirmed','0152-calendar-renewal'
) action;
SET LOCAL timezone='UTC';
CREATE TABLE public.fixture_0152_calendar_event AS
SELECT event.* FROM app_data.promotion_target_retention_events event
JOIN public.fixture_0152_calendar_receipt receipt ON receipt.target_id=event.promotion_target_id;
DO $historical_receipt$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0152_calendar_event)<>1
    OR EXISTS (SELECT 1 FROM public.fixture_0152_calendar_receipt receipt
      JOIN public.fixture_0152_calendar_event event ON event.promotion_target_id=receipt.target_id
      WHERE (receipt.result->>'duplicate')::boolean IS DISTINCT FROM false
        OR (receipt.result->>'review_due_at')::timestamptz IS DISTINCT FROM event.review_due_at
        OR event.review_due_at IS DISTINCT FROM
          ((event.occurred_at AT TIME ZONE 'America/New_York')+interval '6 months') AT TIME ZONE 'America/New_York')
  THEN RAISE EXCEPTION '0152 baseline did not seed its normal non-UTC renewal receipt'; END IF;
END
$historical_receipt$;
CREATE TABLE public.fixture_0152_calendar_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0152_calendar_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0152_retention_calendar_assert_upgrade()
RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  saved public.fixture_0152_calendar_snapshot%ROWTYPE;
  receipt public.fixture_0152_calendar_receipt%ROWTYPE;
  replayed jsonb;
  calculation record;
  original_source text;
  actual_source text;
  due_oid oid := 'app_data.promotion_target_review_due_at(uuid)'::regprocedure;
  renew_oid oid := 'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)'::regprocedure;
  tasks_oid oid := 'app_data.list_promotion_target_retention_tasks(uuid,uuid,uuid)'::regprocedure;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0152_calendar_snapshot;
  SELECT * INTO STRICT receipt FROM public.fixture_0152_calendar_receipt;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0153 retention calendar verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0152_calendar_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid IN (due_oid,renew_oid,tasks_oid)
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0152→0153 changed business facts or function metadata beyond three arithmetic bodies'; END IF;

  FOR calculation IN SELECT * FROM (VALUES
    (due_oid,
      $old$app_data.promotion_target_retention_reference_at(
      target_row.promotion_target_id
    ) + make_interval(months => COALESCE(
      policy_row.retention_months,
      12
    ))$old$,
      $new$pg_catalog.date_add(app_data.promotion_target_retention_reference_at(
      target_row.promotion_target_id
    ), make_interval(months => COALESCE(
      policy_row.retention_months,
      12
    )), 'UTC')$new$),
    (renew_oid,
      $old$event_time + make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12))$old$,
      $new$pg_catalog.date_add(GREATEST(event_time,
        app_data.promotion_target_retention_reference_at(requested_target_id)
      ), make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12)), 'UTC')$new$),
    (tasks_oid,$old$clock_timestamp() + interval '30 days'$old$,$new$clock_timestamp() + interval '720 hours'$new$)
  ) calculations(function_oid,old_expression,new_expression) LOOP
    SELECT catalog_row->>'prosrc' INTO STRICT original_source
    FROM public.fixture_0152_calendar_catalog WHERE oid=calculation.function_oid;
    SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=calculation.function_oid;
    IF length(original_source)-length(replace(original_source,calculation.old_expression,''))
        <>length(calculation.old_expression)
      OR strpos(original_source,calculation.new_expression)<>0
      OR actual_source IS DISTINCT FROM replace(original_source,calculation.old_expression,calculation.new_expression)
    THEN RAISE EXCEPTION '0152→0153 changed function % beyond its exact arithmetic block',calculation.function_oid; END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM public.fixture_0152_calendar_event frozen
    LEFT JOIN app_data.promotion_target_retention_events live USING(event_id)
    WHERE to_jsonb(live) IS DISTINCT FROM to_jsonb(frozen))
  THEN RAISE EXCEPTION '0153 changed a historical renewal event or its stored deadline'; END IF;
  IF app_data.promotion_target_review_due_at(receipt.target_id) IS DISTINCT FROM (
    SELECT ((event.occurred_at AT TIME ZONE 'UTC')+interval '6 months') AT TIME ZONE 'UTC'
    FROM public.fixture_0152_calendar_event event
    WHERE event.promotion_target_id=receipt.target_id AND event.actor_app_user_id=receipt.app_user_id)
  THEN RAISE EXCEPTION '0153 current deadline did not use UTC calendar months from the historical renewal'; END IF;
  PERFORM set_config('TimeZone','Pacific/Kiritimati',true);
  SELECT result INTO STRICT replayed FROM app_data.apply_promotion_target_retention_action(
    receipt.app_user_id,receipt.workspace_id,receipt.project_id,receipt.target_id,
    'renew','purpose_confirmed','0152-calendar-renewal'
  );
  IF (replayed->>'duplicate')::boolean IS DISTINCT FROM true
    OR replayed-'duplicate'-'review_due_at' IS DISTINCT FROM receipt.result-'duplicate'-'review_due_at'
    OR (replayed->>'review_due_at')::timestamptz IS DISTINCT FROM (receipt.result->>'review_due_at')::timestamptz
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events WHERE promotion_target_id=receipt.target_id)<>1
  THEN RAISE EXCEPTION '0153 cross-zone exact replay changed the historical receipt instant or appended an event'; END IF;
  PERFORM set_config('TimeZone','UTC',true);
  IF pg_temp.fixture_database_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0153 historical replay changed business facts'; END IF;
END
$function$;
