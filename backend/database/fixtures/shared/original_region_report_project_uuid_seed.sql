-- Caller supplies original_region_project_id and owns BEGIN/COMMIT/ROLLBACK.
-- The same real release seed covers the 0109 legacy row and 0110 hex UUID.
\set ON_ERROR_STOP on
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0110_actor AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0110.example', :'original_region_project_id');
CREATE TEMP TABLE fixture_0110_org AS
SELECT * FROM app_private.create_organization_v1(
  (SELECT app_user_id FROM fixture_0110_actor),gen_random_uuid(),'0110 report organization');
CREATE TEMP TABLE fixture_0110_context AS
SELECT actor.app_user_id,org.organization_workspace_id AS workspace_id,
  :'original_region_project_id'::uuid AS project_id,
  gen_random_uuid() AS questionnaire_version_id,gen_random_uuid() AS release_request_id,
  'fixture-0110-' || :'original_region_project_id' AS tree_version,
  transaction_timestamp() AS cutoff
FROM fixture_0110_actor actor CROSS JOIN fixture_0110_org org;
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT project_id,workspace_id,'0110 report project' FROM fixture_0110_context;
INSERT INTO app_data.questionnaire_versions(questionnaire_version_id,project_id,version_number,status,is_current)
SELECT questionnaire_version_id,project_id,1,'published',true FROM fixture_0110_context;
CREATE TEMP TABLE fixture_0110_membership AS
SELECT assigned.* FROM fixture_0110_context context CROSS JOIN fixture_0110_org org
CROSS JOIN LATERAL app_private.assign_organization_project_member_v1(
  context.app_user_id,gen_random_uuid(),context.workspace_id,context.project_id,
  org.organization_membership_id) assigned;
INSERT INTO app_data.management_report_capability_grants(capability_grant_id,project_membership_id,capability_id,active_from_utc)
SELECT gen_random_uuid(),project_membership_id,'release_management_reports',active_from_utc
FROM fixture_0110_membership;
SELECT app_private.configure_project_reporting_time_zone_v1(
  gen_random_uuid(),app_user_id,project_id,0,'UTC',cutoff-interval '365 days')
FROM fixture_0110_context;

INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current)
SELECT tree_version,'draft',false FROM fixture_0110_context;
INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind)
SELECT tree_version || '-country',tree_version,NULL,'0110 country','country' FROM fixture_0110_context
UNION ALL
SELECT tree_version || '-city',tree_version,tree_version || '-country','0110 city','city' FROM fixture_0110_context;
INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
SELECT tree_version || '-boundary',tree_version || '-city',tree_version,
  polygon '((-88,41),(-87,41),(-87,42),(-88,42))' FROM fixture_0110_context;
SELECT app_private.publish_canonical_region_tree_v1(tree_version,false) FROM fixture_0110_context;
CREATE TEMP TABLE fixture_0110_contacts AS
SELECT context.*,period_key,'fixture-0110-' || project_id || '-' || period_key AS contact_id,
  (periods->(period_key || '_period')->>'start_utc')::timestamptz AS occurred_at_utc
FROM fixture_0110_context context
CROSS JOIN LATERAL (SELECT app_private.resolve_management_report_periods_v1('UTC',cutoff) AS periods) resolved
CROSS JOIN (VALUES ('previous'),('current')) period(period_key);
INSERT INTO app_data.contacts(contact_id,app_user_id,workspace_id,project_id,questionnaire_version_id,
  occurred_at_utc,occurred_time_zone,first_submitted_at_utc,channel,location_kind,place_name,
  smallest_region_id,region_tree_version,reach_count,interest_level)
SELECT contact_id,app_user_id,workspace_id,project_id,questionnaire_version_id,occurred_at_utc,
  'UTC',occurred_at_utc,'face_to_face','resolved','0110 source city',tree_version || '-city',tree_version,1,2
FROM fixture_0110_contacts;
INSERT INTO app_data.contact_revisions(contact_id,revision_number,revision_kind,revised_by_app_user_id,snapshot)
SELECT contact_id,1,'submitted',app_user_id,jsonb_build_object('contactId',contact_id,
  'location',jsonb_build_object('kind','resolved','placeName','0110 source city',
    'smallestRegionId',tree_version || '-city','regionTreeVersion',tree_version))
FROM fixture_0110_contacts;
INSERT INTO app_data.change_feed(app_user_id,workspace_id,project_id,aggregate_id,revision_number,change_type)
SELECT app_user_id,workspace_id,project_id,contact_id,1,'contact.submitted' FROM fixture_0110_contacts;
CREATE TEMP TABLE fixture_0110_receipt AS
SELECT app_private.release_management_original_region_report_snapshot_v1(
  release_request_id,app_user_id,project_id,'contact_sessions_by_original_region_two_periods',1) AS receipt
FROM fixture_0110_context;

DO $release$
DECLARE context fixture_0110_context%ROWTYPE;
  receipt jsonb := (SELECT saved.receipt FROM fixture_0110_receipt saved);
BEGIN
  SELECT * INTO STRICT context FROM fixture_0110_context;
  IF receipt->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR receipt->>'project_id' IS DISTINCT FROM context.project_id::text
    OR receipt->>'source_tree_version' IS DISTINCT FROM context.tree_version
    OR receipt->'reason_codes' IS DISTINCT FROM '[]'::jsonb
    OR (SELECT count(*) FROM app_private.management_report_snapshots snapshot
      WHERE snapshot.snapshot_id=(receipt->>'released_snapshot_id')::uuid
        AND snapshot.project_id=context.project_id
        AND snapshot.protected_report->>'project_id'=context.project_id::text
        AND snapshot.protected_report->>'result_status'='completed'
        AND jsonb_array_length(snapshot.protected_report->'cells')=2) <> 1
    OR (SELECT count(*) FROM app_private.management_original_region_report_release_attempts attempt
      WHERE attempt.release_request_id=context.release_request_id AND attempt.result_document=receipt) <> 1
    OR (SELECT count(*) FROM app_private.management_report_release_request_claims claim
      WHERE claim.release_request_id=context.release_request_id
        AND claim.release_family_id='original_region_management_report_snapshot_release') <> 1
    OR app_private.release_management_original_region_report_snapshot_v1(
      context.release_request_id,context.app_user_id,context.project_id,
      'contact_sessions_by_original_region_two_periods',1) IS DISTINCT FROM receipt THEN
    RAISE EXCEPTION '0110 real original-region release/receipt/replay drift for %',context.project_id;
  END IF;
END
$release$;
