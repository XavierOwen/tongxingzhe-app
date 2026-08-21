-- 0062_management_interest_report_snapshot_lineage.sql
--
-- Slice 6AW gives the protected 6AV interest distribution its own immutable
-- snapshot lineage.  It deliberately does not reuse the channel or
-- current-city provenance tables or their release-family identifiers.

DO $release_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_management_interest_snapshot_release_writer'
  ) THEN
    CREATE ROLE tongxingzhe_management_interest_snapshot_release_writer
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$release_role$;

ALTER ROLE tongxingzhe_management_interest_snapshot_release_writer
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

-- The snapshot table is shared storage, but the dedicated release writers
-- must not cross report families.  Each SECURITY DEFINER release function
-- therefore sees and inserts only its own fixed report lineage.  The table
-- owner keeps the existing channel, authorized-read and maintenance paths.
ALTER TABLE app_private.management_report_snapshots
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY management_current_city_snapshot_release_writer_scope
ON app_private.management_report_snapshots
FOR ALL
TO tongxingzhe_management_current_city_snapshot_release_writer
USING (
  report_id = 'contact_sessions_by_current_city_two_periods'
  AND release_lineage_id =
    'management-region-report:' || report_id
)
WITH CHECK (
  report_id = 'contact_sessions_by_current_city_two_periods'
  AND release_lineage_id =
    'management-region-report:' || report_id
);

CREATE POLICY management_interest_snapshot_release_writer_scope
ON app_private.management_report_snapshots
FOR ALL
TO tongxingzhe_management_interest_snapshot_release_writer
USING (
  report_id = 'contact_sessions_by_interest_level_two_periods'
  AND release_lineage_id =
    'management-interest-report:' || report_id
)
WITH CHECK (
  report_id = 'contact_sessions_by_interest_level_two_periods'
  AND release_lineage_id =
    'management-interest-report:' || report_id
);

CREATE TABLE app_private.management_interest_report_release_attempts (
  release_request_id uuid PRIMARY KEY,
  requested_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id),
  organization_workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id),
  organization_membership_id uuid NOT NULL
    REFERENCES app_data.organization_memberships (
      organization_membership_id
    ),
  project_membership_id uuid NOT NULL
    REFERENCES app_data.project_memberships (project_membership_id),
  capability_grant_id uuid NOT NULL
    REFERENCES app_data.management_report_capability_grants (
      capability_grant_id
    ),
  capability_id text NOT NULL CHECK (
    capability_id = 'release_management_reports'
  ),
  authorization_reference_at_utc timestamp with time zone NOT NULL,
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  reporting_time_zone_version_number integer NOT NULL
    CHECK (reporting_time_zone_version_number > 0),
  reporting_time_zone text NOT NULL,
  reporting_time_zone_effective_from_utc
    timestamp with time zone NOT NULL,
  data_cutoff_utc timestamp with time zone NOT NULL,
  release_lineage_id text NOT NULL CHECK (
    release_lineage_id =
      'management-interest-report:' || report_id
  ),
  report_id text NOT NULL CHECK (
    report_id = 'contact_sessions_by_interest_level_two_periods'
  ),
  report_version integer NOT NULL CHECK (report_version = 1),
  query_fingerprint text NOT NULL CHECK (
    query_fingerprint =
      'management-report:contact_sessions_by_interest_level_two_periods:v1'
  ),
  source_change_sequence bigint NOT NULL CHECK (source_change_sequence >= 0),
  compared_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  released_snapshot_id uuid NULL UNIQUE
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  shared_period_count integer NOT NULL CHECK (
    shared_period_count >= 0 AND shared_period_count <= 2
  ),
  assessed_cell_count integer NOT NULL CHECK (
    assessed_cell_count = shared_period_count * 5
  ),
  result_status text NOT NULL CHECK (
    result_status IN ('approved_baseline', 'approved', 'blocked')
  ),
  reason_codes jsonb NOT NULL CHECK (jsonb_typeof(reason_codes) = 'array'),
  result_document jsonb NOT NULL
    CHECK (jsonb_typeof(result_document) = 'object'),
  FOREIGN KEY (
    project_id,
    reporting_time_zone_version_number
  ) REFERENCES app_private.project_reporting_time_zone_versions (
    project_id,
    version_number
  ),
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(reporting_time_zone_effective_from_utc)),
  CHECK (isfinite(data_cutoff_utc)),
  CHECK (authorization_reference_at_utc = data_cutoff_utc),
  CHECK (reporting_time_zone_effective_from_utc <= data_cutoff_utc),
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

CREATE INDEX management_interest_report_release_attempts_lineage_idx
ON app_private.management_interest_report_release_attempts (
  project_id,
  release_lineage_id,
  data_cutoff_utc DESC,
  release_request_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_interest_report_release_attempts
  FROM PUBLIC, tongxingzhe_runtime;

-- 0057 established the value-free cross-report request ledger. Extend its
-- closed family set rather than creating a second ledger that could drift.
DO $drop_claim_family_checks$
DECLARE
  constraint_name text;
  dropped_constraint_count integer := 0;
BEGIN
  FOR constraint_name IN
    SELECT constraint_row.conname
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid =
        'app_private.management_report_release_request_claims'::regclass
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        LIKE '%release_family_id%'
  LOOP
    EXECUTE format(
      'ALTER TABLE app_private.management_report_release_request_claims '
        || 'DROP CONSTRAINT %I',
      constraint_name
    );
    dropped_constraint_count = dropped_constraint_count + 1;
  END LOOP;

  IF dropped_constraint_count <> 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'management report release family constraint is inconsistent';
  END IF;
END
$drop_claim_family_checks$;
ALTER TABLE app_private.management_report_release_request_claims
  ADD CONSTRAINT management_report_release_request_claims_family_check
  CHECK (release_family_id IN (
    'channel_management_report_snapshot_release',
    'current_city_management_report_snapshot_release',
    'interest_management_report_snapshot_release'
  ));

CREATE OR REPLACE FUNCTION app_private.claim_management_report_release_request_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  expected_release_family_id text;
  claimed_release_family_id text;
BEGIN
  IF TG_NARGS <> 1 OR TG_ARGV[0] NOT IN (
    'management_report_snapshot_release_v1',
    'trusted_management_report_snapshot_release_v2',
    'current_city_management_report_snapshot_release_v1',
    'interest_management_report_snapshot_release_v1'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'invalid management report release request claim trigger';
  END IF;

  IF TG_ARGV[0] = 'current_city_management_report_snapshot_release_v1' THEN
    expected_release_family_id =
      'current_city_management_report_snapshot_release';
  ELSIF TG_ARGV[0] = 'interest_management_report_snapshot_release_v1' THEN
    expected_release_family_id =
      'interest_management_report_snapshot_release';
  ELSE
    -- Trusted v2 delegates storage to v1 and intentionally shares the
    -- channel family claim.  It remains mutually exclusive with both
    -- current-city and interest release requests.
    expected_release_family_id = 'channel_management_report_snapshot_release';
  END IF;

  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id,
    release_family_id
  ) VALUES (
    NEW.release_request_id,
    expected_release_family_id
  )
  ON CONFLICT (release_request_id) DO NOTHING;

  SELECT claim.release_family_id
  INTO STRICT claimed_release_family_id
  FROM app_private.management_report_release_request_claims AS claim
  WHERE claim.release_request_id = NEW.release_request_id;

  IF claimed_release_family_id <> expected_release_family_id THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'release request id was already used by another report contract';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_interest_report_release_request_claim
BEFORE INSERT
ON app_private.management_interest_report_release_attempts
FOR EACH ROW
EXECUTE FUNCTION app_private.claim_management_report_release_request_v1(
  'interest_management_report_snapshot_release_v1'
);

CREATE TRIGGER management_interest_report_release_attempts_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_interest_report_release_attempts
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

-- The shared immutable snapshot trigger must dispatch the 6AV document to its
-- own validator.  Interest documents keep data_cutoff_utc inside periods and
-- do not expose the source watermark in the protected report itself.
CREATE OR REPLACE FUNCTION app_private.validate_management_report_snapshot_insert_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
BEGIN
  IF NEW.report_id = 'contact_sessions_by_current_city_two_periods' THEN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      NEW.protected_report
    );
  ELSIF NEW.report_id = 'contact_sessions_by_interest_level_two_periods' THEN
    PERFORM app_private.validate_management_interest_report_document_v1(
      NEW.protected_report
    );
  ELSE
    PERFORM app_private.validate_management_report_document_v1(
      NEW.protected_report
    );
  END IF;

  IF NEW.protected_report->>'project_id' <> NEW.project_id::text
    OR NEW.protected_report->>'report_id' <> NEW.report_id
    OR (NEW.protected_report->>'report_version')::integer
      <> NEW.report_version
    OR NEW.protected_report->>'query_fingerprint'
      <> NEW.query_fingerprint
    OR NEW.protected_report->'periods'->>'reporting_time_zone'
      <> NEW.reporting_time_zone
    OR (NEW.protected_report->'periods'->>'data_cutoff_utc')::timestamptz
      <> NEW.data_cutoff_utc
    OR (
      NEW.report_id = 'contact_sessions_by_current_city_two_periods'
      AND (NEW.protected_report->>'source_change_sequence')::bigint
        <> NEW.source_change_sequence
    )
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

DROP TRIGGER management_report_snapshots_validate_insert
  ON app_private.management_report_snapshots;
CREATE TRIGGER management_report_snapshots_validate_insert
BEFORE INSERT
ON app_private.management_report_snapshots
FOR EACH ROW
EXECUTE FUNCTION app_private.validate_management_report_snapshot_insert_v2();

CREATE FUNCTION app_private.validate_management_interest_report_document_v1(
  requested_report jsonb
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  report_data_cutoff timestamp with time zone;
  previous_start timestamp with time zone;
  previous_until timestamp with time zone;
  current_start timestamp with time zone;
  current_until timestamp with time zone;
  expected_periods jsonb;
BEGIN
  IF requested_report IS NULL
    OR jsonb_typeof(requested_report) <> 'object'
    OR requested_report - ARRAY[
      'report_id', 'report_version', 'metric_id', 'metric_version',
      'statistical_unit', 'dimension', 'query_fingerprint',
      'privacy_policy', 'source_scope', 'project_id', 'periods', 'cells'
    ] <> '{}'::jsonb
    OR NOT requested_report ?& ARRAY[
      'report_id', 'report_version', 'metric_id', 'metric_version',
      'statistical_unit', 'dimension', 'query_fingerprint',
      'privacy_policy', 'source_scope', 'project_id', 'periods', 'cells'
    ]
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report document';
  END IF;

  IF requested_report->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_interest_level_two_periods'
    OR requested_report->'report_version' <> '1'::jsonb
    OR requested_report->>'metric_id' IS DISTINCT FROM 'interest_distribution'
    OR requested_report->'metric_version' <> '1'::jsonb
    OR requested_report->>'statistical_unit' IS DISTINCT FROM 'contact_session'
    OR requested_report->>'dimension' IS DISTINCT FROM 'interest_level'
    OR requested_report->>'query_fingerprint' IS DISTINCT FROM
      'management-report:contact_sessions_by_interest_level_two_periods:v1'
    OR requested_report->>'privacy_policy' IS DISTINCT FROM
      'management_interest_distribution_privacy_v1'
    OR requested_report->>'source_scope' IS DISTINCT FROM
      'backend_accepted_active_contacts_current_revision'
    OR jsonb_typeof(requested_report->'project_id') <> 'string'
    OR requested_report->>'project_id'
      !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    OR jsonb_typeof(requested_report->'periods') <> 'object'
    OR jsonb_typeof(requested_report->'cells') <> 'array'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report document';
  END IF;

  BEGIN
    -- Keep the cast as part of the document contract.  The release path
    -- separately verifies that this project is the authorized project.
    PERFORM (requested_report->>'project_id')::uuid;
    report_data_cutoff = (
      requested_report->'periods'->>'data_cutoff_utc'
    )::timestamptz;
  EXCEPTION
    WHEN invalid_text_representation
      OR invalid_datetime_format
      OR datetime_field_overflow
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report document';
  END;

  IF NOT isfinite(report_data_cutoff) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report document';
  END IF;

  IF NOT ((requested_report->'periods') ?& ARRAY[
      'period_boundary_id', 'reporting_time_zone', 'data_cutoff_utc',
      'previous_period', 'current_period'
    ])
    OR (requested_report->'periods') - ARRAY[
      'period_boundary_id', 'reporting_time_zone', 'data_cutoff_utc',
      'previous_period', 'current_period'
    ] <> '{}'::jsonb
    OR requested_report->'periods'->>'period_boundary_id'
      IS DISTINCT FROM 'iso_week_monday_v1'
    OR app_private.management_report_time_zone_valid_v1(
      requested_report->'periods'->>'reporting_time_zone'
    ) IS NOT TRUE
    OR jsonb_typeof(requested_report->'periods'->'data_cutoff_utc')
      <> 'string'
    OR jsonb_typeof(requested_report->'periods'->'previous_period')
      <> 'object'
    OR jsonb_typeof(requested_report->'periods'->'current_period')
      <> 'object'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report periods';
  END IF;

  IF NOT ((requested_report->'periods'->'previous_period') ?& ARRAY[
      'start_utc', 'until_utc'
    ])
    OR (requested_report->'periods'->'previous_period') - ARRAY[
      'start_utc', 'until_utc'
    ] <> '{}'::jsonb
    OR NOT ((requested_report->'periods'->'current_period') ?& ARRAY[
      'start_utc', 'until_utc'
    ])
    OR (requested_report->'periods'->'current_period') - ARRAY[
      'start_utc', 'until_utc'
    ] <> '{}'::jsonb
    OR jsonb_typeof(
      requested_report->'periods'->'previous_period'->'start_utc'
    ) <> 'string'
    OR jsonb_typeof(
      requested_report->'periods'->'previous_period'->'until_utc'
    ) <> 'string'
    OR jsonb_typeof(
      requested_report->'periods'->'current_period'->'start_utc'
    ) <> 'string'
    OR jsonb_typeof(
      requested_report->'periods'->'current_period'->'until_utc'
    ) <> 'string'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report periods';
  END IF;

  BEGIN
    previous_start = (
      requested_report->'periods'->'previous_period'->>'start_utc'
    )::timestamptz;
    previous_until = (
      requested_report->'periods'->'previous_period'->>'until_utc'
    )::timestamptz;
    current_start = (
      requested_report->'periods'->'current_period'->>'start_utc'
    )::timestamptz;
    current_until = (
      requested_report->'periods'->'current_period'->>'until_utc'
    )::timestamptz;
  EXCEPTION
    WHEN invalid_text_representation
      OR invalid_datetime_format
      OR datetime_field_overflow
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report periods';
  END;

  IF NOT isfinite(previous_start)
    OR NOT isfinite(previous_until)
    OR NOT isfinite(current_start)
    OR NOT isfinite(current_until)
    OR previous_start >= previous_until
    OR previous_until <> current_start
    OR current_start >= current_until
    OR current_until > report_data_cutoff
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report periods';
  END IF;

  expected_periods = app_private.resolve_management_report_periods_v1(
    requested_report->'periods'->>'reporting_time_zone',
    report_data_cutoff
  );
  IF requested_report->'periods' IS DISTINCT FROM expected_periods THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report periods';
  END IF;

  IF jsonb_array_length(requested_report->'cells') <> 10
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_report->'cells') AS element(cell)
      WHERE jsonb_typeof(element.cell) <> 'object'
        OR NOT element.cell ?& ARRAY[
          'period_key', 'interest_level', 'cell_order', 'value_count',
          'privacy_status'
        ]
        OR element.cell - ARRAY[
          'period_key', 'interest_level', 'cell_order', 'value_count',
          'privacy_status'
        ] <> '{}'::jsonb
        OR jsonb_typeof(element.cell->'period_key') <> 'string'
        OR element.cell->>'period_key' NOT IN ('previous', 'current')
        OR jsonb_typeof(element.cell->'interest_level') <> 'number'
        OR element.cell->>'interest_level' !~ '^[0-4]$'
        OR jsonb_typeof(element.cell->'cell_order') <> 'number'
        OR element.cell->>'cell_order' !~ '^(0|[1-9][0-9]*)$'
        OR length(element.cell->>'cell_order') > 10
        OR (
          length(element.cell->>'cell_order') = 10
          AND (element.cell->>'cell_order') COLLATE "C" > '2147483647'
        )
        OR jsonb_typeof(element.cell->'privacy_status') <> 'string'
        OR element.cell->>'privacy_status' NOT IN ('displayed', 'suppressed')
        OR (
          element.cell->>'privacy_status' = 'displayed'
          AND (
            jsonb_typeof(element.cell->'value_count') <> 'number'
            OR element.cell->>'value_count' !~ '^(0|[1-9][0-9]*)$'
            OR length(element.cell->>'value_count') > 16
            OR (element.cell->>'value_count')::numeric < 10
            OR (element.cell->>'value_count')::numeric > 9007199254740991
          )
        )
        OR (
          element.cell->>'privacy_status' = 'suppressed'
          AND element.cell->'value_count' <> 'null'::jsonb
        )
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report grid';
  END IF;

  -- Physical array order is part of this contract.  Period-wide privacy is
  -- intentional: 6AV hides all five levels when one level is unsafe.
  IF EXISTS (
    WITH expected(period_key, interest_level, cell_order) AS (
      VALUES
        ('previous'::text, 0, 0), ('previous'::text, 1, 1),
        ('previous'::text, 2, 2), ('previous'::text, 3, 3),
        ('previous'::text, 4, 4), ('current'::text, 0, 5),
        ('current'::text, 1, 6), ('current'::text, 2, 7),
        ('current'::text, 3, 8), ('current'::text, 4, 9)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_report->'cells')
      WITH ORDINALITY AS element(cell, ordinality)
    FULL JOIN expected
      ON expected.period_key = element.cell->>'period_key'
     AND expected.interest_level = (element.cell->>'interest_level')::integer
     AND expected.cell_order = (element.cell->>'cell_order')::integer
     AND expected.cell_order = element.ordinality - 1
    WHERE expected.cell_order IS NULL OR element.cell IS NULL
  )
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_report->'cells') AS element(cell)
    GROUP BY element.cell->>'period_key'
    HAVING count(DISTINCT element.cell->>'privacy_status') > 1
  )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report grid';
  END IF;
END
$function$;

CREATE FUNCTION app_private.assess_management_interest_report_pair_release_v1(
  requested_earlier_report jsonb,
  requested_later_report jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  shared_period_count integer;
  assessed_cell_count integer;
  privacy_status_changed boolean;
  displayed_value_changed boolean;
  reason_codes jsonb = '[]'::jsonb;
BEGIN
  PERFORM app_private.validate_management_interest_report_document_v1(
    requested_earlier_report
  );
  PERFORM app_private.validate_management_interest_report_document_v1(
    requested_later_report
  );

  IF requested_earlier_report->>'project_id' IS DISTINCT FROM
      requested_later_report->>'project_id'
    OR requested_earlier_report->>'report_id' IS DISTINCT FROM
      requested_later_report->>'report_id'
    OR requested_earlier_report->'report_version' IS DISTINCT FROM
      requested_later_report->'report_version'
    OR requested_earlier_report->>'query_fingerprint' IS DISTINCT FROM
      requested_later_report->>'query_fingerprint'
    OR requested_earlier_report->>'privacy_policy' IS DISTINCT FROM
      requested_later_report->>'privacy_policy'
    OR requested_earlier_report->>'source_scope' IS DISTINCT FROM
      requested_later_report->>'source_scope'
    OR requested_earlier_report->>'dimension' IS DISTINCT FROM
      requested_later_report->>'dimension'
    OR requested_earlier_report->'periods'->>'reporting_time_zone'
      IS DISTINCT FROM requested_later_report->'periods'->>'reporting_time_zone'
    OR (requested_earlier_report->'periods'->>'data_cutoff_utc')::timestamptz
      >= (requested_later_report->'periods'->>'data_cutoff_utc')::timestamptz
  THEN
    reason_codes = reason_codes || jsonb_build_array(
      'release_lineage_context_changed'
    );
  END IF;

  WITH earlier_cells AS (
    SELECT
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_earlier_report->'periods'->'previous_period'->>'start_utc'
        ELSE requested_earlier_report->'periods'->'current_period'->>'start_utc'
      END AS start_utc,
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_earlier_report->'periods'->'previous_period'->>'until_utc'
        ELSE requested_earlier_report->'periods'->'current_period'->>'until_utc'
      END AS until_utc,
      (cell->>'interest_level')::integer AS interest_level,
      cell->>'privacy_status' AS privacy_status,
      cell->>'value_count' AS value_count
    FROM jsonb_array_elements(requested_earlier_report->'cells')
      AS element(cell)
  ),
  later_cells AS (
    SELECT
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_later_report->'periods'->'previous_period'->>'start_utc'
        ELSE requested_later_report->'periods'->'current_period'->>'start_utc'
      END AS start_utc,
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_later_report->'periods'->'previous_period'->>'until_utc'
        ELSE requested_later_report->'periods'->'current_period'->>'until_utc'
      END AS until_utc,
      (cell->>'interest_level')::integer AS interest_level,
      cell->>'privacy_status' AS privacy_status,
      cell->>'value_count' AS value_count
    FROM jsonb_array_elements(requested_later_report->'cells')
      AS element(cell)
  ),
  shared_cells AS (
    SELECT
      earlier_cells.start_utc,
      earlier_cells.until_utc,
      earlier_cells.interest_level,
      earlier_cells.privacy_status AS earlier_privacy_status,
      later_cells.privacy_status AS later_privacy_status,
      earlier_cells.value_count AS earlier_value_count,
      later_cells.value_count AS later_value_count
    FROM earlier_cells
    JOIN later_cells
      ON later_cells.start_utc = earlier_cells.start_utc
     AND later_cells.until_utc = earlier_cells.until_utc
     AND later_cells.interest_level = earlier_cells.interest_level
  )
  SELECT
    count(DISTINCT (start_utc, until_utc))::integer,
    count(*)::integer,
    coalesce(bool_or(
      earlier_privacy_status <> later_privacy_status
    ), false),
    coalesce(bool_or(
      earlier_privacy_status = 'displayed'
      AND later_privacy_status = 'displayed'
      AND earlier_value_count <> later_value_count
    ), false)
  INTO
    shared_period_count,
    assessed_cell_count,
    privacy_status_changed,
    displayed_value_changed
  FROM shared_cells;

  IF shared_period_count = 0 THEN
    reason_codes = reason_codes || jsonb_build_array('no_shared_period');
  END IF;
  IF privacy_status_changed THEN
    reason_codes = reason_codes || jsonb_build_array(
      'shared_cell_privacy_status_changed'
    );
  END IF;
  IF displayed_value_changed THEN
    reason_codes = reason_codes || jsonb_build_array(
      'shared_displayed_value_changed'
    );
  END IF;

  RETURN jsonb_build_object(
    'assessment_id', 'management_interest_report_pair_release_v1',
    'report_id', requested_earlier_report->'report_id',
    'report_version', requested_earlier_report->'report_version',
    'query_fingerprint', requested_earlier_report->'query_fingerprint',
    'privacy_policy', requested_earlier_report->'privacy_policy',
    'project_id', requested_earlier_report->'project_id',
    'reporting_time_zone',
      requested_earlier_report->'periods'->'reporting_time_zone',
    'earlier_data_cutoff_utc',
      requested_earlier_report->'periods'->'data_cutoff_utc',
    'later_data_cutoff_utc',
      requested_later_report->'periods'->'data_cutoff_utc',
    'shared_period_count', shared_period_count,
    'assessed_cell_count', assessed_cell_count,
    'result_status', CASE
      WHEN jsonb_array_length(reason_codes) = 0 THEN 'approved'
      ELSE 'blocked'
    END,
    'reason_codes', reason_codes
  );
END
$function$;

CREATE FUNCTION app_private.validate_management_interest_report_release_attempt_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, app_data
AS $function$
DECLARE
  delegated_snapshot app_private.management_report_snapshots%ROWTYPE;
  expected_result_document jsonb;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(NEW.reason_codes) AS reason(code)
    WHERE jsonb_typeof(reason.code) <> 'string'
      OR reason.code #>> '{}' NOT IN (
        'release_lineage_missing_interest_provenance',
        'release_time_zone_revision_changed',
        'release_lineage_context_changed',
        'release_cutoff_not_advanced',
        'release_source_watermark_regressed',
        'no_shared_period',
        'shared_cell_privacy_status_changed',
        'shared_displayed_value_changed'
      )
  ) OR (
    SELECT count(*) <> count(DISTINCT reason.code #>> '{}')
    FROM jsonb_array_elements(NEW.reason_codes) AS reason(code)
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report release reason codes';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS app_user
    JOIN app_data.organization_memberships AS organization_membership
      ON organization_membership.app_user_id = app_user.app_user_id
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id =
        organization_membership.organization_workspace_id
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.organization_membership_id =
        organization_membership.organization_membership_id
    JOIN app_data.projects AS project_row
      ON project_row.project_id = project_membership.project_id
    JOIN app_data.management_report_capability_grants AS capability_grant
      ON capability_grant.project_membership_id =
        project_membership.project_membership_id
    WHERE app_user.app_user_id = NEW.requested_by_app_user_id
      AND app_user.status = 'active'
      AND organization_membership.organization_membership_id =
        NEW.organization_membership_id
      AND organization_membership.organization_workspace_id =
        NEW.organization_workspace_id
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
      AND project_membership.project_membership_id = NEW.project_membership_id
      AND project_membership.project_id = NEW.project_id
      AND project_row.status = 'active'
      AND capability_grant.capability_grant_id = NEW.capability_grant_id
      AND capability_grant.capability_id = NEW.capability_id
      AND tstzrange(
        organization_membership.active_from_utc,
        organization_membership.inactive_from_utc,
        '[)'
      ) @> NEW.authorization_reference_at_utc
      AND tstzrange(
        project_membership.active_from_utc,
        project_membership.inactive_from_utc,
        '[)'
      ) @> NEW.authorization_reference_at_utc
      AND tstzrange(
        capability_grant.active_from_utc,
        capability_grant.inactive_from_utc,
        '[)'
      ) @> NEW.authorization_reference_at_utc
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report release authorization lineage';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.project_reporting_time_zone_versions AS version_row
    WHERE version_row.project_id = NEW.project_id
      AND version_row.version_number = NEW.reporting_time_zone_version_number
      AND version_row.reporting_time_zone = NEW.reporting_time_zone
      AND version_row.effective_from_utc =
        NEW.reporting_time_zone_effective_from_utc
      AND NOT EXISTS (
        SELECT 1
        FROM app_private.project_reporting_time_zone_versions AS later_version
        WHERE later_version.project_id = NEW.project_id
          AND later_version.effective_from_utc <= NEW.data_cutoff_utc
          AND (
            later_version.effective_from_utc > version_row.effective_from_utc
            OR (
              later_version.effective_from_utc = version_row.effective_from_utc
              AND later_version.version_number > version_row.version_number
            )
          )
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report release time zone lineage';
  END IF;

  IF NEW.compared_snapshot_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = NEW.compared_snapshot_id
      AND snapshot.project_id = NEW.project_id
      AND snapshot.release_lineage_id = NEW.release_lineage_id
      AND snapshot.report_id = NEW.report_id
      AND snapshot.report_version = NEW.report_version
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report comparison lineage';
  END IF;

  IF NEW.released_snapshot_id IS NOT NULL THEN
    SELECT snapshot.*
    INTO STRICT delegated_snapshot
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = NEW.released_snapshot_id;

    IF delegated_snapshot.release_request_id <> NEW.release_request_id
      OR delegated_snapshot.created_by_app_user_id <>
        NEW.requested_by_app_user_id
      OR delegated_snapshot.project_id <> NEW.project_id
      OR delegated_snapshot.release_lineage_id <> NEW.release_lineage_id
      OR delegated_snapshot.report_id <> NEW.report_id
      OR delegated_snapshot.report_version <> NEW.report_version
      OR delegated_snapshot.query_fingerprint <> NEW.query_fingerprint
      OR delegated_snapshot.reporting_time_zone <> NEW.reporting_time_zone
      OR delegated_snapshot.data_cutoff_utc <> NEW.data_cutoff_utc
      OR delegated_snapshot.source_change_sequence <>
        NEW.source_change_sequence
      OR delegated_snapshot.previous_snapshot_id IS DISTINCT FROM
        NEW.compared_snapshot_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid management interest report release snapshot lineage';
    END IF;
  END IF;

  expected_result_document = jsonb_build_object(
    'release_contract_id',
      'interest_management_report_snapshot_release_v1',
    'release_request_id', NEW.release_request_id,
    'project_id', NEW.project_id,
    'release_lineage_id', NEW.release_lineage_id,
    'report_id', NEW.report_id,
    'report_version', NEW.report_version,
    'query_fingerprint', NEW.query_fingerprint,
    'reporting_time_zone_version_number',
      NEW.reporting_time_zone_version_number,
    'reporting_time_zone', NEW.reporting_time_zone,
    'data_cutoff_utc', to_char(
      NEW.data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'source_change_sequence', NEW.source_change_sequence,
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
      MESSAGE = 'invalid management interest report release result document';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_interest_report_release_attempts_validate_insert
BEFORE INSERT
ON app_private.management_interest_report_release_attempts
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_interest_report_release_attempt_insert_v1();

CREATE FUNCTION app_private.resolve_management_interest_release_authorization_v1(
  requested_app_user_id uuid,
  requested_project_id uuid
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
  SELECT app_private.resolve_management_report_authorization_v1(
    requested_app_user_id,
    requested_project_id,
    'release_management_reports'
  )
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_interest_report_document_v1(jsonb),
  app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb),
  app_private.validate_management_interest_report_release_attempt_insert_v1(),
  app_private.resolve_management_interest_release_authorization_v1(uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_report_reader;

CREATE FUNCTION app_private.release_management_interest_report_snapshot_v1(
  requested_release_request_id uuid,
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_report_id text,
  requested_report_version integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private, app_data
AS $function$
DECLARE
  existing_attempt
    app_private.management_interest_report_release_attempts%ROWTYPE;
  previous_snapshot app_private.management_report_snapshots%ROWTYPE;
  previous_attempt
    app_private.management_interest_report_release_attempts%ROWTYPE;
  authorization_evidence jsonb;
  canonical_request jsonb;
  candidate_report jsonb;
  release_assessment jsonb;
  release_result jsonb;
  time_zone_version
    app_private.project_reporting_time_zone_versions%ROWTYPE;
  release_lineage_id_value text;
  query_fingerprint_value text;
  data_cutoff_utc_value timestamp with time zone;
  source_change_sequence_value bigint := 0;
  compared_snapshot_id_value uuid;
  released_snapshot_id_value uuid;
  result_status_value text;
  reason_codes_value jsonb := '[]'::jsonb;
  shared_period_count_value integer := 0;
  assessed_cell_count_value integer := 0;
  previous_snapshot_found boolean := false;
  previous_attempt_found boolean := false;
  claimed_release_family_id text;
BEGIN
  IF requested_release_request_id IS NULL
    OR requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_report_id IS DISTINCT FROM
      'contact_sessions_by_interest_level_two_periods'
    OR requested_report_version IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest report release request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_interest_release_authorization_v1(
      requested_app_user_id,
      requested_project_id
    );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-release-request:'
        || requested_release_request_id::text,
      0
    )
  );

  -- Re-resolve after waiting on the request lock. Authorization is consumed
  -- at the database time that linearizes this release attempt.
  authorization_evidence =
    app_private.resolve_management_interest_release_authorization_v1(
      requested_app_user_id,
      requested_project_id
    );

  SELECT attempt.*
  INTO existing_attempt
  FROM app_private.management_interest_report_release_attempts AS attempt
  WHERE attempt.release_request_id = requested_release_request_id;
  IF FOUND THEN
    IF existing_attempt.requested_by_app_user_id <> requested_app_user_id
      OR existing_attempt.project_id <> requested_project_id
      OR existing_attempt.report_id <> requested_report_id
      OR existing_attempt.report_version <> requested_report_version
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'management interest report release idempotency conflict';
    END IF;
    RETURN existing_attempt.result_document;
  END IF;

  SELECT claim.release_family_id
  INTO claimed_release_family_id
  FROM app_private.management_report_release_request_claims AS claim
  WHERE claim.release_request_id = requested_release_request_id;
  IF FOUND
    AND claimed_release_family_id <>
      'interest_management_report_snapshot_release'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'release request id was already used by another report contract';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-reporting-time-zone:' || requested_project_id::text,
      0
    )
  );

  canonical_request =
    app_private.canonicalize_management_interest_distribution_report_request_v1(
      jsonb_build_object(
        'report_id', requested_report_id,
        'report_version', requested_report_version
      )
    );
  query_fingerprint_value = canonical_request->>'query_fingerprint';
  release_lineage_id_value =
    'management-interest-report:' || requested_report_id;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-interest-report-release-lineage:'
        || requested_project_id::text || ':' || release_lineage_id_value,
      0
    )
  );

  -- Re-resolve after all locks which may wait.  The same reference timestamp
  -- supplies both authorization evidence and the trusted report cutoff.
  authorization_evidence =
    app_private.resolve_management_interest_release_authorization_v1(
      requested_app_user_id,
      requested_project_id
    );
  data_cutoff_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT version_row.*
  INTO time_zone_version
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.effective_from_utc <= data_cutoff_utc_value
  ORDER BY version_row.effective_from_utc DESC,
    version_row.version_number DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'project reporting time zone is not configured';
  END IF;

  SELECT snapshot.*
  INTO previous_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = requested_project_id
    AND snapshot.release_lineage_id = release_lineage_id_value
  ORDER BY snapshot.data_cutoff_utc DESC,
    snapshot.released_at_utc DESC,
    snapshot.snapshot_id DESC
  LIMIT 1;
  previous_snapshot_found = FOUND;
  IF previous_snapshot_found THEN
    compared_snapshot_id_value = previous_snapshot.snapshot_id;
    source_change_sequence_value = previous_snapshot.source_change_sequence;
    SELECT attempt.*
    INTO previous_attempt
    FROM app_private.management_interest_report_release_attempts AS attempt
    WHERE attempt.released_snapshot_id = previous_snapshot.snapshot_id;
    previous_attempt_found = FOUND;
    IF NOT previous_attempt_found THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_lineage_missing_interest_provenance'
      );
    ELSIF previous_attempt.reporting_time_zone_version_number <>
        time_zone_version.version_number
    THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_time_zone_revision_changed'
      );
    ELSIF previous_snapshot.report_id <> requested_report_id
      OR previous_snapshot.report_version <> requested_report_version
      OR previous_snapshot.query_fingerprint <> query_fingerprint_value
      OR previous_snapshot.reporting_time_zone <>
        time_zone_version.reporting_time_zone
      OR previous_attempt.project_id <> requested_project_id
      OR previous_attempt.release_lineage_id <> release_lineage_id_value
    THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_lineage_context_changed'
      );
    END IF;
  END IF;

  IF result_status_value IS NULL THEN
    -- Keep the protected document and source watermark in one statement
    -- snapshot. The 6AV document intentionally has no source watermark field.
    SELECT
      app_private.execute_management_interest_distribution_report_v1(
        requested_project_id,
        time_zone_version.reporting_time_zone,
        data_cutoff_utc_value
      ),
      COALESCE((
        SELECT max(change_row.change_sequence)
        FROM app_data.change_feed AS change_row
        WHERE change_row.project_id = requested_project_id
      ), 0)
    INTO candidate_report, source_change_sequence_value;

    PERFORM app_private.validate_management_interest_report_document_v1(
      candidate_report
    );

    IF previous_snapshot_found
      AND previous_snapshot.data_cutoff_utc >= data_cutoff_utc_value
    THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array('release_cutoff_not_advanced');
    ELSIF previous_snapshot_found
      AND previous_snapshot.source_change_sequence >
        source_change_sequence_value
    THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_source_watermark_regressed'
      );
    ELSIF NOT previous_snapshot_found THEN
      result_status_value = 'approved_baseline';
    ELSE
      release_assessment =
        app_private.assess_management_interest_report_pair_release_v1(
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
      query_fingerprint_value,
      time_zone_version.reporting_time_zone,
      data_cutoff_utc_value,
      data_cutoff_utc_value,
      compared_snapshot_id_value,
      source_change_sequence_value,
      candidate_report
    );
  END IF;

  release_result = jsonb_build_object(
    'release_contract_id',
      'interest_management_report_snapshot_release_v1',
    'release_request_id', requested_release_request_id,
    'project_id', requested_project_id,
    'release_lineage_id', release_lineage_id_value,
    'report_id', requested_report_id,
    'report_version', requested_report_version,
    'query_fingerprint', query_fingerprint_value,
    'reporting_time_zone_version_number', time_zone_version.version_number,
    'reporting_time_zone', time_zone_version.reporting_time_zone,
    'data_cutoff_utc', to_char(
      data_cutoff_utc_value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'source_change_sequence', source_change_sequence_value,
    'compared_snapshot_id', compared_snapshot_id_value,
    'released_snapshot_id', released_snapshot_id_value,
    'shared_period_count', shared_period_count_value,
    'assessed_cell_count', assessed_cell_count_value,
    'result_status', result_status_value,
    'reason_codes', reason_codes_value
  );

  INSERT INTO app_private.management_interest_report_release_attempts (
    release_request_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    reporting_time_zone_version_number,
    reporting_time_zone,
    reporting_time_zone_effective_from_utc,
    data_cutoff_utc,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
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
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    authorization_evidence->>'capability_id',
    (authorization_evidence->>'reference_at_utc')::timestamptz,
    requested_project_id,
    time_zone_version.version_number,
    time_zone_version.reporting_time_zone,
    time_zone_version.effective_from_utc,
    data_cutoff_utc_value,
    release_lineage_id_value,
    requested_report_id,
    requested_report_version,
    query_fingerprint_value,
    source_change_sequence_value,
    compared_snapshot_id_value,
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
  app_private.release_management_interest_report_snapshot_v1(
    uuid, uuid, uuid, text, integer
  )
  FROM PUBLIC, tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_report_reader;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_interest_snapshot_release_writer;

REVOKE ALL PRIVILEGES ON
  app_private.project_reporting_time_zone_versions,
  app_private.management_report_snapshots,
  app_private.management_interest_report_release_attempts
  FROM tongxingzhe_management_interest_snapshot_release_writer;

REVOKE ALL PRIVILEGES ON app_data.change_feed
  FROM tongxingzhe_management_interest_snapshot_release_writer;
REVOKE ALL PRIVILEGES ON
  app_private.management_report_release_request_claims
  FROM tongxingzhe_management_interest_snapshot_release_writer;

GRANT SELECT ON app_private.project_reporting_time_zone_versions,
  app_private.management_report_snapshots
  TO tongxingzhe_management_interest_snapshot_release_writer;
GRANT INSERT, SELECT
  ON app_private.management_report_snapshots,
    app_private.management_interest_report_release_attempts
  TO tongxingzhe_management_interest_snapshot_release_writer;
GRANT SELECT ON app_private.management_report_release_request_claims
  TO tongxingzhe_management_interest_snapshot_release_writer;
GRANT SELECT (project_id, change_sequence)
  ON app_data.change_feed
  TO tongxingzhe_management_interest_snapshot_release_writer;

GRANT EXECUTE ON FUNCTION
  app_private.management_report_time_zone_valid_v1(text),
  app_private.resolve_management_report_periods_v1(
    text, timestamp with time zone
  ),
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    jsonb
  ),
  app_private.execute_management_interest_distribution_report_v1(
    uuid, text, timestamp with time zone
  ),
  app_private.validate_management_interest_report_document_v1(jsonb),
  app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb),
  app_private.resolve_management_interest_release_authorization_v1(uuid,uuid),
  app_private.release_management_interest_report_snapshot_v1(
    uuid, uuid, uuid, text, integer
  )
  TO tongxingzhe_management_interest_snapshot_release_writer;

GRANT EXECUTE ON FUNCTION
  app_private.validate_management_interest_report_document_v1(jsonb),
  app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb),
  app_private.release_management_interest_report_snapshot_v1(
    uuid, uuid, uuid, text, integer
  )
  TO CURRENT_USER;

GRANT tongxingzhe_management_interest_snapshot_release_writer TO CURRENT_USER;

ALTER FUNCTION app_private.validate_management_interest_report_document_v1(jsonb)
  OWNER TO tongxingzhe_management_interest_snapshot_release_writer;
ALTER FUNCTION app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)
  OWNER TO tongxingzhe_management_interest_snapshot_release_writer;
ALTER FUNCTION app_private.release_management_interest_report_snapshot_v1(
  uuid, uuid, uuid, text, integer
)
  OWNER TO tongxingzhe_management_interest_snapshot_release_writer;

REVOKE tongxingzhe_management_interest_snapshot_release_writer FROM CURRENT_USER;

DO $release_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname =
      'tongxingzhe_management_interest_snapshot_release_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_interest_snapshot_release_writer FROM %I',
      member_name
    );
  END LOOP;
END
$release_membership$;

COMMENT ON TABLE app_private.management_interest_report_release_attempts
IS 'Immutable private interest-report release provenance; it is separate from channel and current-city release families.';

COMMENT ON FUNCTION app_private.validate_management_interest_report_document_v1(jsonb)
IS 'Validates the exact protected 6AV interest distribution document, including the ten-cell grid and whole-period privacy status.';

COMMENT ON FUNCTION app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)
IS 'Compares overlapping UTC periods of two protected interest documents without exposing cell values.';

COMMENT ON FUNCTION app_private.release_management_interest_report_snapshot_v1(
  uuid, uuid, uuid, text, integer
)
IS 'Authorizes and snapshots the fixed 6AV interest report on an independent immutable release lineage; it never creates channel or current-city provenance.';
