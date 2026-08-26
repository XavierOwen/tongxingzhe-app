-- 0081_authorized_management_deidentified_location_anomaly_read.sql
--
-- Slice 6CC exposes a project-scoped, deidentified directory and explicit
-- detail read for current accepted contact-location anomalies. The contract
-- has a dedicated capability, opaque identifiers, a closed reader role and a
-- value-free immutable audit. It does not provide a correction mutation.

DO $reader_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_management_deidentified_anomaly_reader'
  ) THEN
    CREATE ROLE tongxingzhe_management_deidentified_anomaly_reader
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$reader_role$;

ALTER ROLE tongxingzhe_management_deidentified_anomaly_reader
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

ALTER TABLE app_data.management_report_capability_grants
  DROP CONSTRAINT management_report_capability_grants_capability_id_check;

ALTER TABLE app_data.management_report_capability_grants
  ADD CONSTRAINT management_report_capability_grants_capability_id_check
  CHECK (
    capability_id IN (
      'view_anonymous_analytics',
      'release_management_reports',
      'export_management_reports',
      'view_deidentified_anomalies'
    )
  );

CREATE OR REPLACE FUNCTION app_private.resolve_management_report_authorization_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_capability_id text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_record record;
  authorization_workspace_id uuid;
  reference_at_utc timestamp with time zone;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_capability_id IS NULL
    OR requested_capability_id NOT IN (
      'view_anonymous_analytics',
      'release_management_reports',
      'export_management_reports',
      'view_deidentified_anomalies'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report authorization request';
  END IF;

  SELECT project_row.workspace_id INTO authorization_workspace_id
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = requested_project_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:' || authorization_workspace_id::text
        || ':' || requested_app_user_id::text,
      0
    )
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'project-membership:' || requested_project_id::text
        || ':' || requested_app_user_id::text,
      0
    )
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'management-report-capability:' || requested_project_id::text
        || ':' || requested_app_user_id::text
        || ':' || requested_capability_id,
      0
    )
  );

  reference_at_utc = clock_timestamp();

  SELECT
    workspace_row.workspace_id,
    organization_membership.organization_membership_id,
    project_membership.project_membership_id,
    capability_grant.capability_grant_id,
    capability_grant.active_from_utc AS capability_active_from_utc,
    capability_grant.inactive_from_utc AS capability_inactive_from_utc
  INTO authorization_record
  FROM app_data.app_users AS app_user
  JOIN app_data.organization_memberships AS organization_membership
    ON organization_membership.app_user_id = app_user.app_user_id
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.workspace_id =
      organization_membership.organization_workspace_id
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
  JOIN app_data.project_memberships AS project_membership
    ON project_membership.organization_membership_id =
      organization_membership.organization_membership_id
   AND project_membership.project_id = project_row.project_id
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.project_membership_id =
      project_membership.project_membership_id
  WHERE app_user.app_user_id = requested_app_user_id
    AND app_user.status = 'active'
    AND workspace_row.workspace_kind = 'organization'
    AND workspace_row.deleted_at IS NULL
    AND project_row.project_id = requested_project_id
    AND project_row.status = 'active'
    AND tstzrange(
      organization_membership.active_from_utc,
      organization_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND tstzrange(
      project_membership.active_from_utc,
      project_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND capability_grant.capability_id = requested_capability_id
    AND tstzrange(
      capability_grant.active_from_utc,
      capability_grant.inactive_from_utc,
      '[)'
    ) @> reference_at_utc;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  RETURN jsonb_build_object(
    'authorization_contract_id', 'management_report_authorization_v1',
    'app_user_id', requested_app_user_id,
    'organization_workspace_id', authorization_record.workspace_id,
    'project_id', requested_project_id,
    'organization_membership_id',
      authorization_record.organization_membership_id,
    'project_membership_id', authorization_record.project_membership_id,
    'capability_grant_id', authorization_record.capability_grant_id,
    'capability_id', requested_capability_id,
    'capability_active_from_utc', to_char(
      authorization_record.capability_active_from_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'capability_inactive_from_utc', CASE
      WHEN authorization_record.capability_inactive_from_utc IS NULL
        THEN NULL
      ELSE to_char(
        authorization_record.capability_inactive_from_utc
          AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    END,
    'reference_at_utc', to_char(
      reference_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  );
END
$function$;

-- Wait for any in-flight provenance writer before the one-time backfill. New
-- inserts remain blocked until the opaque-ID trigger is installed at commit,
-- so no eligible source can fall into the backfill/trigger migration window.
LOCK TABLE app_data.contact_location_provenance
IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE app_private.deidentified_location_anomaly_ids (
  anomaly_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id uuid NOT NULL UNIQUE
    REFERENCES app_data.contact_location_provenance (source_id)
    ON DELETE RESTRICT,
  mapped_at_utc timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CHECK (isfinite(mapped_at_utc))
);

-- Assign opaque identifiers to every immutable provenance row that can ever
-- represent one of the two version-1 anomaly reasons. Current-project and
-- current-revision eligibility is deliberately rechecked at read time.
INSERT INTO app_private.deidentified_location_anomaly_ids (source_id)
SELECT source.source_id
FROM app_data.contact_location_provenance AS source
WHERE source.revision_kind IN ('submitted', 'corrected')
  AND (
    (
      source.location_kind = 'pending_resolution'
      AND source.evidence_kind = 'pending_coordinates'
    ) OR (
      source.location_kind = 'unknown'
      AND source.evidence_kind = 'legacy_incomplete'
    )
  )
ON CONFLICT (source_id) DO NOTHING;

CREATE FUNCTION
  app_private.capture_deidentified_location_anomaly_id_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NEW.revision_kind IN ('submitted', 'corrected')
    AND (
      (
        NEW.location_kind = 'pending_resolution'
        AND NEW.evidence_kind = 'pending_coordinates'
      ) OR (
        NEW.location_kind = 'unknown'
        AND NEW.evidence_kind = 'legacy_incomplete'
      )
    )
  THEN
    INSERT INTO app_private.deidentified_location_anomaly_ids (source_id)
    VALUES (NEW.source_id)
    ON CONFLICT (source_id) DO NOTHING;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER contact_location_provenance_map_deidentified_anomaly
AFTER INSERT
ON app_data.contact_location_provenance
FOR EACH ROW
EXECUTE FUNCTION
  app_private.capture_deidentified_location_anomaly_id_v1();

CREATE TABLE app_private.deidentified_location_anomaly_access_events (
  access_event_id uuid PRIMARY KEY,
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
    capability_id = 'view_deidentified_anomalies'
  ),
  authorization_reference_at_utc timestamp with time zone NOT NULL,
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  access_kind text NOT NULL CHECK (access_kind IN ('directory', 'detail')),
  result_status text NOT NULL CHECK (
    result_status IN ('completed', 'not_found')
  ),
  returned_anomaly_count integer CHECK (
    returned_anomaly_count BETWEEN 0 AND 20
  ),
  accessed_at_utc timestamp with time zone NOT NULL,
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(accessed_at_utc)),
  CHECK (authorization_reference_at_utc = accessed_at_utc),
  CHECK (
    (
      access_kind = 'directory'
      AND result_status = 'completed'
      AND returned_anomaly_count IS NOT NULL
    ) OR (
      access_kind = 'detail'
      AND returned_anomaly_count IS NULL
    )
  )
);

CREATE INDEX deidentified_location_anomaly_access_events_project_idx
ON app_private.deidentified_location_anomaly_access_events (
  project_id,
  accessed_at_utc DESC,
  access_event_id DESC
);

ALTER TABLE app_private.deidentified_location_anomaly_ids
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.deidentified_location_anomaly_ids
  FORCE ROW LEVEL SECURITY;
ALTER TABLE app_private.deidentified_location_anomaly_access_events
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.deidentified_location_anomaly_access_events
  FORCE ROW LEVEL SECURITY;

CREATE POLICY deidentified_location_anomaly_ids_reader_policy
ON app_private.deidentified_location_anomaly_ids
FOR ALL
TO tongxingzhe_management_deidentified_anomaly_reader
USING (true)
WITH CHECK (true);

CREATE POLICY deidentified_location_anomaly_access_reader_policy
ON app_private.deidentified_location_anomaly_access_events
FOR ALL
TO tongxingzhe_management_deidentified_anomaly_reader
USING (true)
WITH CHECK (true);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.deidentified_location_anomaly_ids,
  app_private.deidentified_location_anomaly_access_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER deidentified_location_anomaly_ids_immutable
BEFORE UPDATE OR DELETE
ON app_private.deidentified_location_anomaly_ids
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE TRIGGER deidentified_location_anomaly_access_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.deidentified_location_anomaly_access_events
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION app_private.validate_deidentified_location_anomaly_access_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
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
      AND project_membership.project_membership_id =
        NEW.project_membership_id
      AND project_membership.project_id = NEW.project_id
      AND project_row.workspace_id = NEW.organization_workspace_id
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
      MESSAGE = 'invalid deidentified anomaly access authorization';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER deidentified_location_anomaly_access_events_validate
BEFORE INSERT
ON app_private.deidentified_location_anomaly_access_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_deidentified_location_anomaly_access_v1();

CREATE FUNCTION
  app_private.list_authorized_deidentified_location_anomalies_v1(
    requested_app_user_id uuid,
    requested_project_id uuid
  )
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_evidence jsonb;
  authorization_reference_at_utc_value timestamp with time zone;
  access_event_id_value uuid := gen_random_uuid();
  anomaly_directory jsonb;
  returned_count integer;
BEGIN
  IF requested_app_user_id IS NULL OR requested_project_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid deidentified anomaly directory request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'view_deidentified_anomalies'
    );
  authorization_reference_at_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'anomaly_id', directory_row.anomaly_id,
          'reason_code', directory_row.reason_code,
          'status', 'open',
          'occurred_at_utc', to_char(
            directory_row.occurred_at_utc AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
          ),
          'location_kind', directory_row.location_kind,
          'evidence_kind', directory_row.evidence_kind,
          'has_usable_coordinates', directory_row.has_usable_coordinates
        ) ORDER BY
          directory_row.occurred_at_utc DESC,
          directory_row.anomaly_id DESC
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  INTO anomaly_directory, returned_count
  FROM (
    SELECT
      mapping.anomaly_id,
      contact.occurred_at_utc,
      source.location_kind,
      source.evidence_kind,
      CASE source.evidence_kind
        WHEN 'pending_coordinates' THEN 'pending_resolution'
        ELSE 'legacy_incomplete'
      END AS reason_code,
      source.evidence_kind = 'pending_coordinates'
        AS has_usable_coordinates
    FROM app_private.deidentified_location_anomaly_ids AS mapping
    JOIN app_data.contact_location_provenance AS source
      ON source.source_id = mapping.source_id
    JOIN app_data.contacts AS contact
      ON contact.contact_id = source.contact_id
     AND contact.current_revision = source.revision_number
    JOIN app_data.contact_revisions AS revision
      ON revision.contact_id = source.contact_id
     AND revision.revision_number = source.revision_number
     AND revision.revision_kind = source.revision_kind
    WHERE contact.project_id = requested_project_id
      AND contact.lifecycle_status = 'active'
      AND source.revision_kind IN ('submitted', 'corrected')
      AND (
        (
          source.location_kind = 'pending_resolution'
          AND source.evidence_kind = 'pending_coordinates'
        ) OR (
          source.location_kind = 'unknown'
          AND source.evidence_kind = 'legacy_incomplete'
        )
      )
    ORDER BY contact.occurred_at_utc DESC, mapping.anomaly_id DESC
    LIMIT 20
  ) AS directory_row;

  INSERT INTO app_private.deidentified_location_anomaly_access_events (
    access_event_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    access_kind,
    result_status,
    returned_anomaly_count,
    accessed_at_utc
  ) VALUES (
    access_event_id_value,
    requested_app_user_id,
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    authorization_evidence->>'capability_id',
    authorization_reference_at_utc_value,
    requested_project_id,
    'directory',
    'completed',
    returned_count,
    authorization_reference_at_utc_value
  );

  RETURN jsonb_build_object(
    'access_contract_id',
      'authorized_deidentified_location_anomaly_directory_v1',
    'access_event_id', access_event_id_value,
    'project_id', requested_project_id,
    'anomalies', anomaly_directory
  );
END
$function$;

CREATE FUNCTION
  app_private.read_authorized_deidentified_location_anomaly_v1(
    requested_app_user_id uuid,
    requested_project_id uuid,
    requested_anomaly_id uuid
  )
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_evidence jsonb;
  authorization_reference_at_utc_value timestamp with time zone;
  access_event_id_value uuid := gen_random_uuid();
  locked_contact_id text;
  anomaly_detail jsonb;
  result_status_value text;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_anomaly_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid deidentified anomaly detail request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'view_deidentified_anomalies'
    );
  authorization_reference_at_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT source.contact_id
  INTO locked_contact_id
  FROM app_private.deidentified_location_anomaly_ids AS mapping
  JOIN app_data.contact_location_provenance AS source
    ON source.source_id = mapping.source_id
  JOIN app_data.contacts AS contact
    ON contact.contact_id = source.contact_id
  WHERE mapping.anomaly_id = requested_anomaly_id
    AND contact.project_id = requested_project_id;

  IF FOUND THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('contact:' || locked_contact_id, 0)
    );
  END IF;

  SELECT jsonb_build_object(
    'anomaly_id', mapping.anomaly_id,
    'reason_code', CASE source.evidence_kind
      WHEN 'pending_coordinates' THEN 'pending_resolution'
      ELSE 'legacy_incomplete'
    END,
    'status', 'open',
    'occurred_at_utc', to_char(
      contact.occurred_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'location_kind', source.location_kind,
    'evidence_kind', source.evidence_kind,
    'has_usable_coordinates',
      source.evidence_kind = 'pending_coordinates',
    'coordinates', CASE
      WHEN source.evidence_kind = 'pending_coordinates' THEN
        jsonb_build_object(
          'latitude', source.latitude,
          'longitude', source.longitude,
          'accuracy_meters', source.accuracy_meters
        )
      ELSE NULL
    END
  )
  INTO anomaly_detail
  FROM app_private.deidentified_location_anomaly_ids AS mapping
  JOIN app_data.contact_location_provenance AS source
    ON source.source_id = mapping.source_id
  JOIN app_data.contacts AS contact
    ON contact.contact_id = source.contact_id
   AND contact.current_revision = source.revision_number
  JOIN app_data.contact_revisions AS revision
    ON revision.contact_id = source.contact_id
   AND revision.revision_number = source.revision_number
   AND revision.revision_kind = source.revision_kind
  WHERE mapping.anomaly_id = requested_anomaly_id
    AND contact.project_id = requested_project_id
    AND contact.lifecycle_status = 'active'
    AND source.revision_kind IN ('submitted', 'corrected')
    AND (
      (
        source.location_kind = 'pending_resolution'
        AND source.evidence_kind = 'pending_coordinates'
      ) OR (
        source.location_kind = 'unknown'
        AND source.evidence_kind = 'legacy_incomplete'
      )
    );

  result_status_value = CASE
    WHEN anomaly_detail IS NULL THEN 'not_found'
    ELSE 'completed'
  END;

  INSERT INTO app_private.deidentified_location_anomaly_access_events (
    access_event_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    access_kind,
    result_status,
    returned_anomaly_count,
    accessed_at_utc
  ) VALUES (
    access_event_id_value,
    requested_app_user_id,
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    authorization_evidence->>'capability_id',
    authorization_reference_at_utc_value,
    requested_project_id,
    'detail',
    result_status_value,
    NULL,
    authorization_reference_at_utc_value
  );

  RETURN jsonb_build_object(
    'access_contract_id',
      'authorized_deidentified_location_anomaly_detail_v1',
    'access_event_id', access_event_id_value,
    'project_id', requested_project_id,
    'result_status', result_status_value,
    'anomaly', anomaly_detail
  );
END
$function$;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (app_user_id, status)
  ON app_data.app_users
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (workspace_id, workspace_kind, deleted_at)
  ON app_data.workspaces
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (project_id, workspace_id, status)
  ON app_data.projects
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) ON app_data.organization_memberships
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) ON app_data.project_memberships
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) ON app_data.management_report_capability_grants
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (
  contact_id,
  project_id,
  occurred_at_utc,
  current_revision,
  lifecycle_status
) ON app_data.contacts
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (
  contact_id,
  revision_number,
  revision_kind
) ON app_data.contact_revisions
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT SELECT (
  source_id,
  contact_id,
  revision_number,
  revision_kind,
  location_kind,
  evidence_kind,
  latitude,
  longitude,
  accuracy_meters
) ON app_data.contact_location_provenance
  TO tongxingzhe_management_deidentified_anomaly_reader;

GRANT EXECUTE ON FUNCTION
  app_private.resolve_management_report_authorization_v1(uuid, uuid, text)
  TO tongxingzhe_management_deidentified_anomaly_reader;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.capture_deidentified_location_anomaly_id_v1(),
  app_private.validate_deidentified_location_anomaly_access_v1(),
  app_private.list_authorized_deidentified_location_anomalies_v1(uuid, uuid),
  app_private.read_authorized_deidentified_location_anomaly_v1(
    uuid, uuid, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_private.list_authorized_deidentified_location_anomalies_v1(uuid, uuid),
  app_private.read_authorized_deidentified_location_anomaly_v1(
    uuid, uuid, uuid
  )
  TO CURRENT_USER;

GRANT tongxingzhe_management_deidentified_anomaly_reader TO CURRENT_USER;
ALTER TABLE app_private.deidentified_location_anomaly_ids
  OWNER TO tongxingzhe_management_deidentified_anomaly_reader;
ALTER TABLE app_private.deidentified_location_anomaly_access_events
  OWNER TO tongxingzhe_management_deidentified_anomaly_reader;
ALTER FUNCTION app_private.capture_deidentified_location_anomaly_id_v1()
  OWNER TO tongxingzhe_management_deidentified_anomaly_reader;
ALTER FUNCTION app_private.validate_deidentified_location_anomaly_access_v1()
  OWNER TO tongxingzhe_management_deidentified_anomaly_reader;
ALTER FUNCTION
  app_private.list_authorized_deidentified_location_anomalies_v1(uuid, uuid)
  OWNER TO tongxingzhe_management_deidentified_anomaly_reader;
ALTER FUNCTION
  app_private.read_authorized_deidentified_location_anomaly_v1(
    uuid, uuid, uuid
  )
  OWNER TO tongxingzhe_management_deidentified_anomaly_reader;
REVOKE tongxingzhe_management_deidentified_anomaly_reader FROM CURRENT_USER;

DO $reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname =
      'tongxingzhe_management_deidentified_anomaly_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_deidentified_anomaly_reader FROM %I',
      member_name
    );
  END LOOP;
END
$reader_membership$;

COMMENT ON TABLE app_private.deidentified_location_anomaly_ids
IS 'Private opaque identifiers for immutable location-provenance rows; current anomaly eligibility is rederived for every authorized read.';

COMMENT ON TABLE app_private.deidentified_location_anomaly_access_events
IS 'Immutable value-free audit for authorized deidentified anomaly directory and detail reads; it stores no anomaly identifier, coordinate, contact, revision, source or PII.';

COMMENT ON FUNCTION
  app_private.list_authorized_deidentified_location_anomalies_v1(uuid, uuid)
IS 'Reauthorizes one project and returns at most twenty current deidentified location anomalies without coordinates.';

COMMENT ON FUNCTION
  app_private.read_authorized_deidentified_location_anomaly_v1(
    uuid, uuid, uuid
  )
IS 'Reauthorizes one project and reads one opaque current anomaly; unknown, cross-project and stale identifiers share value-free not_found semantics.';
