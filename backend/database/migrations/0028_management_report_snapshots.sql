-- 0028_management_report_snapshots.sql
--
-- 在一个私有事务中生成受保护报告、与最近已发布快照比较，并保存不可变
-- 发布历史。被阻止的尝试只保存原因码和审计元数据，不保存候选报告格值。
-- 当前边界仍不执行成员授权，也不向 runtime 开放表或函数。

CREATE TABLE app_private.management_report_snapshots (
  snapshot_id uuid PRIMARY KEY,
  release_request_id uuid NOT NULL UNIQUE,
  created_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  release_lineage_id text NOT NULL,
  report_id text NOT NULL,
  report_version integer NOT NULL CHECK (report_version > 0),
  query_fingerprint text NOT NULL,
  reporting_time_zone text NOT NULL,
  data_cutoff_utc timestamp with time zone NOT NULL,
  released_at_utc timestamp with time zone NOT NULL,
  previous_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  source_change_sequence bigint NOT NULL
    CHECK (source_change_sequence >= 0),
  protected_report jsonb NOT NULL
    CHECK (jsonb_typeof(protected_report) = 'object'),
  CHECK (isfinite(data_cutoff_utc)),
  CHECK (isfinite(released_at_utc)),
  CHECK (data_cutoff_utc <= released_at_utc)
);

CREATE INDEX management_report_snapshots_latest_idx
ON app_private.management_report_snapshots (
  project_id,
  release_lineage_id,
  data_cutoff_utc DESC,
  released_at_utc DESC
);

CREATE TABLE app_private.management_report_release_attempts (
  release_request_id uuid PRIMARY KEY,
  requested_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  release_lineage_id text NOT NULL,
  report_id text NOT NULL,
  report_version integer NOT NULL CHECK (report_version > 0),
  query_fingerprint text NOT NULL,
  reporting_time_zone text NOT NULL,
  data_cutoff_utc timestamp with time zone NOT NULL,
  requested_at_utc timestamp with time zone NOT NULL,
  source_change_sequence bigint NOT NULL
    CHECK (source_change_sequence >= 0),
  compared_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  released_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  shared_period_count integer NOT NULL CHECK (shared_period_count >= 0),
  assessed_cell_count integer NOT NULL CHECK (assessed_cell_count >= 0),
  result_status text NOT NULL CHECK (
    result_status IN ('approved_baseline', 'approved', 'blocked')
  ),
  reason_codes jsonb NOT NULL CHECK (jsonb_typeof(reason_codes) = 'array'),
  result_document jsonb NOT NULL
    CHECK (jsonb_typeof(result_document) = 'object'),
  CHECK (isfinite(data_cutoff_utc)),
  CHECK (isfinite(requested_at_utc)),
  CHECK (data_cutoff_utc <= requested_at_utc),
  CHECK (shared_period_count <= 2),
  CHECK (assessed_cell_count = shared_period_count * 8),
  CHECK (
    (
      result_status = 'approved_baseline'
      AND compared_snapshot_id IS NULL
      AND released_snapshot_id IS NOT NULL
      AND shared_period_count = 0
      AND assessed_cell_count = 0
      AND reason_codes = '[]'::jsonb
    )
    OR (
      result_status = 'approved'
      AND compared_snapshot_id IS NOT NULL
      AND released_snapshot_id IS NOT NULL
      AND shared_period_count > 0
      AND reason_codes = '[]'::jsonb
    )
    OR (
      result_status = 'blocked'
      AND compared_snapshot_id IS NOT NULL
      AND released_snapshot_id IS NULL
      AND jsonb_array_length(reason_codes) > 0
    )
  )
);

CREATE INDEX management_report_release_attempts_project_idx
ON app_private.management_report_release_attempts (
  project_id,
  release_lineage_id,
  requested_at_utc DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_snapshots,
  app_private.management_report_release_attempts
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.reject_management_report_history_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'management report release history is immutable';
END
$function$;

CREATE TRIGGER management_report_snapshots_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_snapshots
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE TRIGGER management_report_release_attempts_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_release_attempts
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.validate_management_report_release_attempt_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  expected_result_document jsonb;
BEGIN
  expected_result_document = jsonb_build_object(
    'release_contract_id', 'management_report_snapshot_release_v1',
    'release_request_id', NEW.release_request_id,
    'project_id', NEW.project_id,
    'release_lineage_id', NEW.release_lineage_id,
    'report_id', NEW.report_id,
    'report_version', NEW.report_version,
    'query_fingerprint', NEW.query_fingerprint,
    'reporting_time_zone', NEW.reporting_time_zone,
    'data_cutoff_utc', to_char(
      NEW.data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'requested_at_utc', to_char(
      NEW.requested_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'compared_snapshot_id', NEW.compared_snapshot_id,
    'released_snapshot_id', NEW.released_snapshot_id,
    'shared_period_count', NEW.shared_period_count,
    'assessed_cell_count', NEW.assessed_cell_count,
    'result_status', NEW.result_status,
    'reason_codes', NEW.reason_codes
  );

  IF NEW.result_document <> expected_result_document THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report release audit document';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_release_attempts_validate_insert
BEFORE INSERT
ON app_private.management_report_release_attempts
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_release_attempt_insert_v1();

CREATE FUNCTION app_private.validate_management_report_snapshot_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  PERFORM app_private.validate_management_report_document_v1(
    NEW.protected_report
  );

  IF NEW.protected_report->>'project_id' <> NEW.project_id::text
    OR NEW.protected_report->>'report_id' <> NEW.report_id
    OR (NEW.protected_report->>'report_version')::integer
      <> NEW.report_version
    OR NEW.protected_report->>'query_fingerprint'
      <> NEW.query_fingerprint
    OR NEW.protected_report->'periods'->>'reporting_time_zone'
      <> NEW.reporting_time_zone
    OR (
      NEW.protected_report->'periods'->>'data_cutoff_utc'
    )::timestamp with time zone <> NEW.data_cutoff_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot metadata';
  END IF;

  IF NEW.previous_snapshot_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM app_private.management_report_snapshots AS previous_snapshot
      WHERE previous_snapshot.snapshot_id = NEW.previous_snapshot_id
        AND previous_snapshot.project_id = NEW.project_id
        AND previous_snapshot.release_lineage_id = NEW.release_lineage_id
        AND previous_snapshot.report_id = NEW.report_id
        AND previous_snapshot.report_version = NEW.report_version
        AND previous_snapshot.query_fingerprint = NEW.query_fingerprint
        AND previous_snapshot.reporting_time_zone = NEW.reporting_time_zone
        AND previous_snapshot.data_cutoff_utc < NEW.data_cutoff_utc
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid previous management report snapshot';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_snapshots_validate_insert
BEFORE INSERT
ON app_private.management_report_snapshots
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_snapshot_insert_v1();

CREATE FUNCTION app_private.read_management_report_snapshot_v1(
  requested_snapshot_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  stored_report jsonb;
BEGIN
  IF requested_snapshot_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot request';
  END IF;

  SELECT snapshot.protected_report INTO STRICT stored_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_snapshot_id;

  RETURN stored_report;
EXCEPTION WHEN no_data_found THEN
  RAISE EXCEPTION USING
    ERRCODE = '22023',
    MESSAGE = 'invalid management report snapshot request';
END
$function$;

CREATE FUNCTION app_private.release_management_report_snapshot_v1(
  requested_release_request_id uuid,
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_report_id text,
  requested_report_version integer,
  requested_reporting_time_zone text,
  requested_data_cutoff_utc timestamp with time zone,
  requested_at_utc timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  existing_attempt
    app_private.management_report_release_attempts%ROWTYPE;
  previous_snapshot app_private.management_report_snapshots%ROWTYPE;
  candidate_report jsonb;
  release_assessment jsonb;
  release_result jsonb;
  registered_fingerprint text;
  release_lineage_id_value text;
  source_change_sequence_value bigint;
  result_status_value text;
  reason_codes_value jsonb := '[]'::jsonb;
  shared_period_count_value integer := 0;
  assessed_cell_count_value integer := 0;
  released_snapshot_id_value uuid;
BEGIN
  IF requested_release_request_id IS NULL
    OR requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_report_id IS NULL
    OR requested_report_version IS NULL
    OR requested_report_version <= 0
    OR requested_data_cutoff_utc IS NULL
    OR NOT isfinite(requested_data_cutoff_utc)
    OR requested_at_utc IS NULL
    OR NOT isfinite(requested_at_utc)
    OR requested_data_cutoff_utc > requested_at_utc
    OR app_private.management_report_time_zone_valid_v1(
      requested_reporting_time_zone
    ) IS NOT TRUE
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.app_users AS app_user
      WHERE app_user.app_user_id = requested_app_user_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report release context';
  END IF;

  release_lineage_id_value =
    'management-report:' || requested_report_id;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-release-request:'
        || requested_release_request_id::text,
      0
    )
  );

  SELECT attempt.* INTO existing_attempt
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id = requested_release_request_id;

  IF FOUND THEN
    IF existing_attempt.requested_by_app_user_id
        <> requested_app_user_id
      OR existing_attempt.project_id <> requested_project_id
      OR existing_attempt.report_id <> requested_report_id
      OR existing_attempt.report_version <> requested_report_version
      OR existing_attempt.reporting_time_zone
        <> requested_reporting_time_zone
      OR existing_attempt.data_cutoff_utc <> requested_data_cutoff_utc
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'management report release idempotency conflict';
    END IF;

    RETURN existing_attempt.result_document;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-release-lineage:'
        || requested_project_id::text
        || ':' || release_lineage_id_value,
      0
    )
  );

  -- The generated report and source watermark must observe one statement
  -- snapshot. Under READ COMMITTED, separate SELECT statements could diverge.
  SELECT
    app_private.execute_management_contact_session_report_v1(
      requested_project_id,
      requested_report_id,
      requested_report_version,
      requested_reporting_time_zone,
      requested_data_cutoff_utc
    ),
    COALESCE((
      SELECT max(change_row.change_sequence)
      FROM app_data.change_feed AS change_row
      WHERE change_row.project_id = requested_project_id
    ), 0)
  INTO candidate_report, source_change_sequence_value;
  PERFORM app_private.validate_management_report_document_v1(
    candidate_report
  );
  registered_fingerprint = candidate_report->>'query_fingerprint';

  SELECT snapshot.* INTO previous_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = requested_project_id
    AND snapshot.release_lineage_id = release_lineage_id_value
  ORDER BY
    snapshot.data_cutoff_utc DESC,
    snapshot.released_at_utc DESC,
    snapshot.snapshot_id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    result_status_value = 'approved_baseline';
  ELSE
    IF previous_snapshot.report_id <> requested_report_id
      OR previous_snapshot.report_version <> requested_report_version
      OR previous_snapshot.query_fingerprint <> registered_fingerprint
      OR previous_snapshot.reporting_time_zone
        <> requested_reporting_time_zone
    THEN
      result_status_value = 'blocked';
      reason_codes_value =
        jsonb_build_array('release_lineage_context_changed');
    ELSIF requested_data_cutoff_utc <= previous_snapshot.data_cutoff_utc
    THEN
      result_status_value = 'blocked';
      reason_codes_value =
        jsonb_build_array('release_cutoff_not_advanced');
    ELSE
      release_assessment =
        app_private.assess_management_report_pair_release_v1(
          previous_snapshot.protected_report,
          candidate_report
        );
      result_status_value = release_assessment->>'result_status';
      reason_codes_value = release_assessment->'reason_codes';
      shared_period_count_value =
        (release_assessment->>'shared_period_count')::integer;
      assessed_cell_count_value =
        (release_assessment->>'assessed_cell_count')::integer;
    END IF;
  END IF;

  IF result_status_value IN ('approved_baseline', 'approved') THEN
    released_snapshot_id_value = gen_random_uuid();

    INSERT INTO app_private.management_report_snapshots (
      snapshot_id,
      release_request_id,
      created_by_app_user_id,
      project_id,
      release_lineage_id,
      report_id,
      report_version,
      query_fingerprint,
      reporting_time_zone,
      data_cutoff_utc,
      released_at_utc,
      previous_snapshot_id,
      source_change_sequence,
      protected_report
    ) VALUES (
      released_snapshot_id_value,
      requested_release_request_id,
      requested_app_user_id,
      requested_project_id,
      release_lineage_id_value,
      requested_report_id,
      requested_report_version,
      registered_fingerprint,
      requested_reporting_time_zone,
      requested_data_cutoff_utc,
      requested_at_utc,
      previous_snapshot.snapshot_id,
      source_change_sequence_value,
      candidate_report
    );
  END IF;

  release_result = jsonb_build_object(
    'release_contract_id', 'management_report_snapshot_release_v1',
    'release_request_id', requested_release_request_id,
    'project_id', requested_project_id,
    'release_lineage_id', release_lineage_id_value,
    'report_id', requested_report_id,
    'report_version', requested_report_version,
    'query_fingerprint', registered_fingerprint,
    'reporting_time_zone', requested_reporting_time_zone,
    'data_cutoff_utc', to_char(
      requested_data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'requested_at_utc', to_char(
      requested_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'compared_snapshot_id', previous_snapshot.snapshot_id,
    'released_snapshot_id', released_snapshot_id_value,
    'shared_period_count', shared_period_count_value,
    'assessed_cell_count', assessed_cell_count_value,
    'result_status', result_status_value,
    'reason_codes', reason_codes_value
  );

  INSERT INTO app_private.management_report_release_attempts (
    release_request_id,
    requested_by_app_user_id,
    project_id,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    reporting_time_zone,
    data_cutoff_utc,
    requested_at_utc,
    source_change_sequence,
    compared_snapshot_id,
    released_snapshot_id,
    shared_period_count,
    assessed_cell_count,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    requested_release_request_id,
    requested_app_user_id,
    requested_project_id,
    release_lineage_id_value,
    requested_report_id,
    requested_report_version,
    registered_fingerprint,
    requested_reporting_time_zone,
    requested_data_cutoff_utc,
    requested_at_utc,
    source_change_sequence_value,
    previous_snapshot.snapshot_id,
    released_snapshot_id_value,
    shared_period_count_value,
    assessed_cell_count_value,
    result_status_value,
    reason_codes_value,
    release_result
  );

  RETURN release_result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.reject_management_report_history_mutation(),
  app_private.validate_management_report_release_attempt_insert_v1(),
  app_private.validate_management_report_snapshot_insert_v1(),
  app_private.read_management_report_snapshot_v1(uuid),
  app_private.release_management_report_snapshot_v1(
    uuid,
    uuid,
    uuid,
    text,
    integer,
    text,
    timestamp with time zone,
    timestamp with time zone
  )
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON TABLE app_private.management_report_snapshots
IS 'Immutable protected report documents approved for release; contains no pre-suppression values.';

COMMENT ON TABLE app_private.management_report_release_attempts
IS 'Immutable release audit metadata; blocked candidates are not stored.';

COMMENT ON FUNCTION app_private.release_management_report_snapshot_v1(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  text,
  timestamp with time zone,
  timestamp with time zone
)
IS 'Generates and conditionally snapshots a protected fixed report under an idempotent project lock; performs no membership authorization.';
