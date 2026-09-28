\set ON_ERROR_STOP on

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
) VALUES (
  '00000000-0000-4000-8000-000000007c11',
  'https://upgrade-runtime-report.synthetic/auth/v1',
  '7cl-viewer',
  '00000000-0000-4000-8000-000000007c02'
);

CREATE TEMP TABLE fixture_7cl_private_read AS
SELECT app_private.read_authorized_management_report_snapshot_v1(
  '00000000-0000-4000-8000-000000007c02',
  '00000000-0000-4000-8000-000000007c05',
  attempt.released_snapshot_id
) AS result
FROM app_private.management_report_release_v2_attempts AS attempt
WHERE attempt.release_request_id =
  '00000000-0000-4000-8000-000000007c0c';

DO $verify$
DECLARE
  result jsonb;
  snapshot_row app_private.management_report_snapshots%ROWTYPE;
  access_row app_private.management_report_snapshot_access_events%ROWTYPE;
BEGIN
  SELECT r.result INTO STRICT result FROM fixture_7cl_private_read AS r;
  SELECT s.* INTO STRICT snapshot_row
  FROM app_private.management_report_snapshots AS s
  WHERE s.release_request_id =
    '00000000-0000-4000-8000-000000007c0c';
  SELECT e.* INTO STRICT access_row
  FROM app_private.management_report_snapshot_access_events AS e;

  IF result <> jsonb_build_object(
    'access_contract_id', 'authorized_management_report_snapshot_read_v1',
    'access_event_id', access_row.access_event_id,
    'requested_snapshot_id', snapshot_row.snapshot_id,
    'resolved_snapshot_id', snapshot_row.snapshot_id,
    'result_status', 'completed',
    'reason_code', NULL,
    'protected_report', snapshot_row.protected_report
  ) OR (SELECT count(*) FROM jsonb_object_keys(to_jsonb(access_row))) <> 17
    OR access_row.requested_by_app_user_id <>
      '00000000-0000-4000-8000-000000007c02'
    OR access_row.organization_workspace_id <>
      '00000000-0000-4000-8000-000000007c03'
    OR access_row.organization_membership_id <>
      '00000000-0000-4000-8000-000000007c07'
    OR access_row.project_membership_id <>
      '00000000-0000-4000-8000-000000007c09'
    OR access_row.capability_grant_id <>
      '00000000-0000-4000-8000-000000007c0b'
    OR access_row.capability_id <> 'view_anonymous_analytics'
    OR access_row.authorization_reference_at_utc <>
      access_row.accessed_at_utc
    OR access_row.project_id <>
      '00000000-0000-4000-8000-000000007c05'
    OR access_row.requested_snapshot_id <> snapshot_row.snapshot_id
    OR access_row.resolved_snapshot_id IS DISTINCT FROM snapshot_row.snapshot_id
    OR access_row.report_id IS DISTINCT FROM snapshot_row.report_id
    OR access_row.report_version IS DISTINCT FROM snapshot_row.report_version
    OR access_row.query_fingerprint IS DISTINCT FROM
      snapshot_row.query_fingerprint
    OR access_row.result_status <> 'completed'
    OR access_row.reason_code IS NOT NULL
    OR to_jsonb(access_row)::text ~*
      '"(protected_report|cells|value_count|contributor|contact_id|reach_count|interest_level|raw_answer)"[[:space:]]*:'
    OR (SELECT count(*)
        FROM app_private.management_report_snapshot_access_events) <> 1
  THEN
    RAISE EXCEPTION '7CL old private read or access audit drift';
  END IF;
END
$verify$;
