\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
) VALUES (
  '00000000-0000-4000-8000-000000007c12',
  'https://upgrade-report-export.synthetic/auth/v1',
  '7cr-viewer',
  '00000000-0000-4000-8000-000000007c02'
);

SELECT released_snapshot_id AS old_snapshot_id
FROM app_private.management_report_release_v2_attempts
WHERE release_request_id =
  '00000000-0000-4000-8000-000000007c0c'
\gset

SET LOCAL ROLE tongxingzhe_runtime;
SELECT app_data.read_authorized_management_report_snapshot_v1(
  'https://upgrade-report-export.synthetic/auth/v1',
  '7cr-viewer',
  '00000000-0000-4000-8000-000000007c05',
  :'old_snapshot_id'::uuid
);
RESET ROLE;

DO $verify$
DECLARE
  audit_row app_private.management_report_snapshot_access_events%ROWTYPE;
  snapshot_row app_private.management_report_snapshots%ROWTYPE;
BEGIN
  SELECT * INTO STRICT audit_row
  FROM app_private.management_report_snapshot_access_events;
  SELECT * INTO STRICT snapshot_row
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '00000000-0000-4000-8000-000000007c0c';

  IF audit_row.requested_by_app_user_id <>
      '00000000-0000-4000-8000-000000007c02'
    OR audit_row.project_id <>
      '00000000-0000-4000-8000-000000007c05'
    OR audit_row.capability_grant_id <>
      '00000000-0000-4000-8000-000000007c0b'
    OR audit_row.capability_id <> 'view_anonymous_analytics'
    OR audit_row.resolved_snapshot_id IS DISTINCT FROM snapshot_row.snapshot_id
    OR audit_row.result_status <> 'completed'
    OR audit_row.reason_code IS NOT NULL
    OR (SELECT count(*)
        FROM app_private.management_report_snapshot_access_events) <> 1
  THEN
    RAISE EXCEPTION '0051 old runtime read or sole audit is invalid';
  END IF;
END
$verify$;

COMMIT;
