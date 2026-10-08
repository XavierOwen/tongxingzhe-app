-- Slice 7DF: one trusted database transaction removes one expired organization.
-- Text composite business receipts are selected by exact business evidence and
-- removed with their payload. They are not UUID completion families: their text
-- keys may be reused for a different personal operation. A replay carrying the
-- deleted W/P cannot read the old accepted result and fails current authorization.
-- External warehouse deliveries, backups and scheduling are outside this seam.
ALTER TABLE app_private.organization_deletion_current
  DROP CONSTRAINT organization_deletion_current_state_check;
ALTER TABLE app_private.organization_deletion_current
  ADD CONSTRAINT organization_deletion_current_state_check CHECK (
    (status IN ('deletion_pending','purge_due','purging','purge_failed')
      AND restored_at_utc IS NULL)
    OR (status='restored' AND restored_at_utc IS NOT NULL)
  );

-- This private query only collects the fixed UUID families. It neither locks
-- nor authorizes rows, and cannot accept a relation or SQL predicate from callers.
CREATE FUNCTION app_private.organization_purge_requests_v1(requested_workspace_id uuid)
RETURNS TABLE(lock_rank integer, lock_namespace text, claim_family text, request_uuid uuid)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
  SELECT 1, 'organization-creation-request', 'organization-creation-request', request_id FROM app_private.organization_creation_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 2, 'organization-directed-account-invitation-request', 'organization-directed-account-invitation-request', invitation_id FROM app_private.organization_directed_account_invitation_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 3, 'organization-owner-transfer-request', 'organization-owner-transfer-request', request_id FROM app_private.organization_owner_transfer_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 4, 'organization-membership-self-leave-request', 'organization-membership-self-leave-request', request_id FROM app_private.organization_membership_self_leave_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 5, 'organization-shareable-join-link-request', 'organization-shareable-join-link-request', link_id FROM app_private.organization_shareable_join_link_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 6, 'organization-shareable-join-application-request', 'organization-shareable-join-application-request', application_id FROM app_private.organization_shareable_join_application_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 7, 'organization-project-membership-assignment-request', 'organization-project-membership-assignment-request', request_id FROM app_private.organization_project_membership_assignment_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 8, 'organization-deletion-request', 'organization-deletion-request', request_id FROM app_private.organization_deletion_request_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 9, 'organization-deletion-restore-request', 'organization-deletion-restore-request', request_id FROM app_private.organization_deletion_restore_claims
  WHERE organization_workspace_id = requested_workspace_id
  UNION
  SELECT 10, 'management-report-release-request', 'channel_management_report_snapshot_release', release_request_id FROM app_private.management_report_release_attempts
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'channel_management_report_snapshot_release', release_request_id FROM app_private.management_report_release_v2_attempts
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'current_city_management_report_snapshot_release', release_request_id FROM app_private.management_current_city_report_release_attempts
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'interest_management_report_snapshot_release', release_request_id FROM app_private.management_interest_report_release_attempts
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'original_region_management_report_snapshot_release', release_request_id FROM app_private.management_original_region_report_release_attempts
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'follow_up_consent_ratio_management_report_snapshot_release', release_request_id FROM app_private.management_follow_up_consent_report_release_attempts
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'original_region_management_report_snapshot_replacement', replacement_request_id FROM app_private.management_original_region_report_snapshot_replacements
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'current_city_management_report_snapshot_replacement', replacement_request_id FROM app_private.management_current_city_report_snapshot_replacements
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'interest_management_report_snapshot_replacement', replacement_request_id FROM app_private.management_interest_report_snapshot_replacements
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 10, 'management-report-release-request', 'follow_up_consent_ratio_management_report_snapshot_replacement', replacement_request_id FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 11, 'management-report-snapshot-replacement-request', 'management-report-snapshot-replacement-request', replacement_request_id FROM app_private.management_report_snapshot_replacements
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 12, 'project-reporting-time-zone-change-request', 'project-reporting-time-zone-change-request', change_request_id FROM app_private.project_reporting_time_zone_versions
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
  UNION
  SELECT 13, 'management-follow-up-consent-opt-in-request', 'management-follow-up-consent-opt-in-request', request_id FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)
$function$;

CREATE FUNCTION app_private.finalize_organization_purge_v1(
  requested_organization_workspace_id uuid,
  expected_deletion_request_id uuid
)
RETURNS TABLE(deletion_request_id uuid, purge_completed_at_utc timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  request_set jsonb;
  rechecked_request_set jsonb;
  request_row record;
  scope_row record;
  selected_row record;
  lock_key text;
  query text;
  cross_root boolean;
  pk_expression text;
  deleted_count bigint;
  remaining_count bigint;
  relation_list text[] := ARRAY[
    'app_data.change_feed',
    'app_data.contact_answers',
    'app_data.contact_attempts',
    'app_data.contact_audit_events',
    'app_data.contact_region_assignments',
    'app_data.contact_revision_conflicts',
    'app_data.contact_target_links',
    'app_data.management_analysis_current_contexts',
    'app_data.organization_owner_assignments',
    'app_data.processed_commands',
    'app_data.promotion_target_access_events',
    'app_data.promotion_target_assignments',
    'app_data.promotion_target_creation_requests',
    'app_data.promotion_target_institution_relation_revisions',
    'app_data.promotion_target_relationship_conflict_resolutions',
    'app_data.promotion_target_relationship_revisions',
    'app_data.promotion_target_retention_events',
    'app_data.promotion_target_retention_policies',
    'app_data.promotion_target_stage_aliases',
    'app_data.questionnaire_metric_members',
    'app_data.questionnaire_options',
    'app_data.questionnaire_publish_requests',
    'app_data.warehouse_outbox',
    'app_private.deidentified_location_anomaly_access_events',
    'app_private.deidentified_location_anomaly_ids',
    'app_private.management_current_city_report_snapshot_access_events',
    'app_private.management_current_city_report_snapshot_directory_access_events',
    'app_private.management_current_city_report_snapshot_replacements',
    'app_private.management_follow_up_consent_opt_in_versions',
    'app_private.management_follow_up_consent_ratio_report_snapshot_replacements',
    'app_private.management_follow_up_consent_report_snapshot_access_events',
    'app_private.management_follow_up_consent_snapshot_directory_access_events',
    'app_private.management_interest_report_snapshot_access_events',
    'app_private.management_interest_report_snapshot_directory_access_events',
    'app_private.management_interest_report_snapshot_replacements',
    'app_private.management_original_region_report_snapshot_access_events',
    'app_private.management_original_region_report_snapshot_replacements',
    'app_private.management_original_region_snapshot_directory_access_events',
    'app_private.management_report_release_request_claims',
    'app_private.management_report_release_v2_attempts',
    'app_private.management_report_snapshot_access_events',
    'app_private.management_report_snapshot_directory_access_events',
    'app_private.management_report_snapshot_export_events',
    'app_private.management_report_snapshot_replacements',
    'app_private.organization_creation_audit_events',
    'app_private.organization_creation_request_claims',
    'app_private.organization_deletion_audit_events',
    'app_private.organization_deletion_request_claims',
    'app_private.organization_deletion_restore_claims',
    'app_private.organization_directed_account_invitation_audit_events',
    'app_private.organization_directed_account_invitation_request_claims',
    'app_private.organization_membership_self_leave_audit_events',
    'app_private.organization_membership_self_leave_request_claims',
    'app_private.organization_owner_transfer_audit_events',
    'app_private.organization_owner_transfer_request_claims',
    'app_private.organization_project_membership_assignment_audit_events',
    'app_private.organization_project_membership_assignment_request_claims',
    'app_private.organization_shareable_join_application_audit_events',
    'app_private.organization_shareable_join_application_request_claims',
    'app_private.organization_shareable_join_link_audit_events',
    'app_private.organization_shareable_join_link_request_claims',
    'app_data.contact_location_provenance',
    'app_data.promotion_target_institution_relationships',
    'app_data.promotion_target_relationship_conflicts',
    'app_data.questionnaire_drafts',
    'app_data.questionnaire_metric_compatibility_events',
    'app_private.management_current_city_report_release_attempts',
    'app_private.management_follow_up_consent_report_release_attempts',
    'app_private.management_interest_report_release_attempts',
    'app_private.management_original_region_report_release_attempts',
    'app_private.management_report_release_attempts',
    'app_data.contact_revisions',
    'app_data.management_report_capability_grants',
    'app_data.promotion_target_project_relationships',
    'app_data.questionnaire_metrics',
    'app_data.questionnaire_questions',
    'app_private.management_report_snapshots',
    'app_private.project_reporting_time_zone_versions',
    'app_data.contacts',
    'app_data.project_memberships',
    'app_data.promotion_targets',
    'app_data.organization_memberships',
    'app_data.questionnaire_versions',
    'app_data.projects',
    'app_data.workspaces',
    'app_private.organization_deletion_current'
  ];
  scope_predicates text[] := ARRAY[
    't.workspace_id = $1 AND t.project_id = ANY($2)',
    't.contact_id = ANY($3)',
    't.workspace_id = $1 AND t.project_id = ANY($2)',
    't.contact_id = ANY($3)',
    't.contact_id = ANY($3)',
    't.workspace_id = $1 AND t.project_id = ANY($2)',
    't.contact_id = ANY($3)',
    't.organization_workspace_id = $1',
    't.organization_membership_id = ANY($7)',
    'EXISTS (SELECT 1 FROM app_data.change_feed f WHERE f.cursor_token=t.server_cursor AND f.workspace_id=$1 AND f.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_data.contact_audit_events a WHERE a.app_user_id=t.app_user_id AND a.command_id=t.command_id AND a.contact_id=ANY($3)) OR EXISTS (SELECT 1 FROM app_data.contact_revision_conflicts c WHERE c.app_user_id=t.app_user_id AND (c.command_id=t.command_id OR c.resolution_command_id=t.command_id) AND c.workspace_id=$1 AND c.project_id=ANY($2))',
    't.workspace_id = $1',
    't.promotion_target_id = ANY($4)',
    't.promotion_target_id = ANY($4)',
    'EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships r WHERE r.relationship_id=t.relationship_id AND r.workspace_id=$1)',
    'EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_conflicts c WHERE c.conflict_id=t.conflict_id AND c.promotion_target_id=ANY($4))',
    't.promotion_target_id = ANY($4)',
    't.workspace_id = $1',
    't.workspace_id = $1',
    't.project_id = ANY($2)',
    'EXISTS (SELECT 1 FROM app_data.questionnaire_metrics m WHERE m.questionnaire_metric_id=t.questionnaire_metric_id AND m.project_id=ANY($2))',
    't.questionnaire_version_id = ANY($5)',
    't.questionnaire_version_id = ANY($5)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    'EXISTS (SELECT 1 FROM app_data.contact_location_provenance p WHERE p.source_id=t.source_id AND p.contact_id=ANY($3))',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    'EXISTS (SELECT 1 FROM app_private.management_report_release_attempts a WHERE a.release_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_report_release_v2_attempts a WHERE a.release_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_current_city_report_release_attempts a WHERE a.release_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_interest_report_release_attempts a WHERE a.release_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_original_region_report_release_attempts a WHERE a.release_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_follow_up_consent_report_release_attempts a WHERE a.release_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_original_region_report_snapshot_replacements a WHERE a.replacement_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_current_city_report_snapshot_replacements a WHERE a.replacement_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_interest_report_snapshot_replacements a WHERE a.replacement_request_id=t.release_request_id AND a.project_id=ANY($2)) OR EXISTS (SELECT 1 FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements a WHERE a.replacement_request_id=t.release_request_id AND a.project_id=ANY($2))',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.organization_workspace_id = $1',
    't.contact_id = ANY($3)',
    't.workspace_id = $1',
    't.promotion_target_id = ANY($4)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.contact_id = ANY($3)',
    't.project_membership_id = ANY($8)',
    't.promotion_target_id = ANY($4)',
    't.project_id = ANY($2)',
    't.questionnaire_version_id = ANY($5)',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.workspace_id = $1 AND t.project_id = ANY($2)',
    't.organization_membership_id = ANY($7)',
    't.workspace_id = $1',
    't.organization_workspace_id = $1',
    't.project_id = ANY($2)',
    't.project_id = ANY($2)',
    't.workspace_id = $1',
    't.organization_workspace_id = $1'
  ];
  gathered_user_ids uuid[];
  project_ids uuid[];
  contact_ids text[];
  target_ids uuid[];
  questionnaire_ids uuid[];
  snapshot_ids uuid[];
  membership_ids uuid[];
  project_membership_ids uuid[];
  affected_user_ids uuid[];
  user_id uuid;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  attempt_row app_private.organization_deletion_current%ROWTYPE;
  reference_time timestamptz;
  terminal_time timestamptz;
BEGIN
  IF requested_organization_workspace_id IS NULL OR expected_deletion_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid organization purge request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge requires read committed';
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations
    WHERE transaction_id=pg_current_xact_id() AND backend_pid=pg_backend_pid()) THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge authorization already present';
  END IF;

  -- Collect before locking, then take each namespace in contract order. The nine
  -- shared management families share one namespace and one UUID-ordered lock set.
  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.lock_rank,r.request_uuid,r.claim_family),'[]'::jsonb)
  INTO request_set FROM (
    SELECT * FROM app_private.organization_purge_requests_v1(requested_organization_workspace_id)
    UNION SELECT 8,'organization-deletion-request','organization-deletion-request',expected_deletion_request_id
  ) r;
  FOR request_row IN SELECT DISTINCT r.lock_rank,r.lock_namespace,r.request_uuid
    FROM jsonb_to_recordset(request_set) AS r(lock_rank integer,lock_namespace text,claim_family text,request_uuid uuid)
    ORDER BY r.lock_rank,r.request_uuid
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(request_row.lock_namespace || ':' || request_row.request_uuid::text,0));
  END LOOP;

  SELECT tombstone.purge_completed_at_utc INTO terminal_time
  FROM app_private.organization_purge_request_tombstones tombstone
  WHERE tombstone.claim_family='organization-deletion-request'
    AND tombstone.request_uuid=expected_deletion_request_id;
  IF FOUND THEN
    -- Value-free completion proves this request ended. With W gone it cannot
    -- establish or rebind the caller's workspace selector to the old request.
    RETURN QUERY SELECT expected_deletion_request_id,terminal_time;
    RETURN;
  END IF;

  SELECT coalesce(array_agg(project_id ORDER BY project_id),'{}'::uuid[]) INTO project_ids
  FROM app_data.projects WHERE workspace_id=requested_organization_workspace_id;
  -- Collect every user reference in the fixed selected scope before governance.
  -- These are preserved identity roots, including retired actors/nonmembers.
  SELECT coalesce(array_agg(contact_id),'{}'::text[]) INTO contact_ids FROM app_data.contacts
  WHERE workspace_id=requested_organization_workspace_id AND project_id=ANY(project_ids);
  SELECT coalesce(array_agg(promotion_target_id),'{}'::uuid[]) INTO target_ids FROM app_data.promotion_targets
  WHERE workspace_id=requested_organization_workspace_id;
  SELECT coalesce(array_agg(questionnaire_version_id),'{}'::uuid[]) INTO questionnaire_ids FROM app_data.questionnaire_versions
  WHERE project_id=ANY(project_ids);
  SELECT coalesce(array_agg(snapshot_id),'{}'::uuid[]) INTO snapshot_ids FROM app_private.management_report_snapshots
  WHERE project_id=ANY(project_ids);
  SELECT coalesce(array_agg(organization_membership_id),'{}'::uuid[]) INTO membership_ids FROM app_data.organization_memberships
  WHERE organization_workspace_id=requested_organization_workspace_id;
  SELECT coalesce(array_agg(project_membership_id),'{}'::uuid[]) INTO project_membership_ids FROM app_data.project_memberships
  WHERE organization_membership_id=ANY(membership_ids);
  affected_user_ids:='{}'::uuid[];
  FOR scope_row IN SELECT relation_name,predicate FROM unnest(relation_list,scope_predicates) scope(relation_name,predicate) LOOP
    EXECUTE format('SELECT coalesce(array_agg(DISTINCT field.value::uuid),''{}''::uuid[])
      FROM %s t CROSS JOIN LATERAL jsonb_each_text(to_jsonb(t)) field
      WHERE (%s) AND field.key LIKE ''%%app_user_id'' AND field.value IS NOT NULL',scope_row.relation_name,scope_row.predicate)
    INTO gathered_user_ids
    USING requested_organization_workspace_id,project_ids,contact_ids,target_ids,questionnaire_ids,snapshot_ids,membership_ids,project_membership_ids;
    affected_user_ids:=affected_user_ids || gathered_user_ids;
  END LOOP;
  SELECT coalesce(array_agg(DISTINCT id ORDER BY id),'{}'::uuid[]) INTO affected_user_ids FROM unnest(affected_user_ids) id;
  FOREACH user_id IN ARRAY affected_user_ids LOOP
    PERFORM 1 FROM app_data.app_users WHERE app_user_id=user_id FOR UPDATE;
  END LOOP;
  PERFORM app_private.lock_organization_governance_v1(requested_organization_workspace_id);
  SELECT w.workspace_kind,w.deleted_at INTO workspace_kind,workspace_deleted_at
  FROM app_data.workspaces w WHERE w.workspace_id=requested_organization_workspace_id FOR UPDATE;
  IF workspace_kind IS DISTINCT FROM 'organization' THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='organization purge forbidden';
  END IF;
  SELECT a.* INTO attempt_row FROM app_private.organization_deletion_current a
  WHERE a.organization_workspace_id=requested_organization_workspace_id FOR UPDATE;

  -- A request or member added while collecting is a whole-transaction retry.
  -- Never obtain an earlier request/user lock after taking governance.
  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.lock_rank,r.request_uuid,r.claim_family),'[]'::jsonb)
  INTO rechecked_request_set FROM (
    SELECT * FROM app_private.organization_purge_requests_v1(requested_organization_workspace_id)
    UNION SELECT 8,'organization-deletion-request','organization-deletion-request',expected_deletion_request_id
  ) r;
  IF request_set IS DISTINCT FROM rechecked_request_set OR EXISTS (
    SELECT 1 FROM app_data.organization_memberships m
    WHERE m.organization_workspace_id=requested_organization_workspace_id
      AND NOT (m.app_user_id=ANY(affected_user_ids))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge collection changed; rollback and retry';
  END IF;

  -- Hierarchy keys and rows precede project/config/lineage locks.
  FOR lock_key IN SELECT 'organization-membership:' || m.organization_workspace_id::text || ':' || m.app_user_id::text
    FROM app_data.organization_memberships m WHERE m.organization_workspace_id=requested_organization_workspace_id
    ORDER BY m.app_user_id LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(lock_key,0));
  END LOOP;
  PERFORM 1 FROM app_data.organization_memberships m WHERE m.organization_workspace_id=requested_organization_workspace_id
    ORDER BY m.organization_membership_id FOR UPDATE;
  SELECT coalesce(array_agg(organization_membership_id ORDER BY organization_membership_id),'{}'::uuid[]) INTO membership_ids
  FROM app_data.organization_memberships WHERE organization_workspace_id=requested_organization_workspace_id;
  PERFORM 1 FROM app_data.organization_owner_assignments o WHERE o.organization_membership_id=ANY(membership_ids)
    ORDER BY o.organization_owner_assignment_id FOR UPDATE;
  FOR lock_key IN SELECT 'project-membership:' || pm.project_id::text || ':' || m.app_user_id::text
    FROM app_data.project_memberships pm JOIN app_data.organization_memberships m USING(organization_membership_id)
    WHERE m.organization_workspace_id=requested_organization_workspace_id
    ORDER BY pm.project_id,m.app_user_id LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(lock_key,0));
  END LOOP;
  PERFORM 1 FROM app_data.project_memberships pm WHERE pm.organization_membership_id=ANY(membership_ids)
    ORDER BY pm.project_membership_id FOR UPDATE;
  SELECT coalesce(array_agg(project_membership_id ORDER BY project_membership_id),'{}'::uuid[]) INTO project_membership_ids
  FROM app_data.project_memberships WHERE organization_membership_id=ANY(membership_ids);
  FOR lock_key IN SELECT 'management-report-capability:' || pm.project_id::text || ':' || m.app_user_id::text || ':' || g.capability_id
    FROM app_data.management_report_capability_grants g JOIN app_data.project_memberships pm USING(project_membership_id)
    JOIN app_data.organization_memberships m USING(organization_membership_id)
    WHERE m.organization_workspace_id=requested_organization_workspace_id
    ORDER BY pm.project_id,m.app_user_id,g.capability_id LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(lock_key,0));
  END LOOP;
  PERFORM 1 FROM app_data.management_report_capability_grants g WHERE g.project_membership_id=ANY(project_membership_ids)
    ORDER BY g.capability_grant_id FOR UPDATE;
  PERFORM 1 FROM app_data.projects p WHERE p.workspace_id=requested_organization_workspace_id ORDER BY p.project_id FOR UPDATE;
  SELECT coalesce(array_agg(project_id ORDER BY project_id),'{}'::uuid[]) INTO project_ids
  FROM app_data.projects WHERE workspace_id=requested_organization_workspace_id;
  FOREACH user_id IN ARRAY project_ids LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('project-reporting-time-zone:' || user_id::text,0));
    PERFORM pg_advisory_xact_lock(hashtextextended('management-follow-up-consent-opt-in:' || user_id::text,0));
  END LOOP;
  FOR lock_key IN SELECT namespace || s.project_id::text || ':' || s.release_lineage_id
    FROM (SELECT DISTINCT project_id,release_lineage_id FROM app_private.management_report_snapshots WHERE project_id=ANY(project_ids)) s
    CROSS JOIN (VALUES ('management-report-release-lineage:'),('management-current-city-release-lineage:'),
      ('management-interest-report-release-lineage:'),('management-original-region-report-release-lineage:'),
      ('management-follow-up-consent-ratio-report-release-lineage:'),('management-report-snapshot-replacement-lineage:'),
      ('management-original-region-snapshot-replacement-lineage:'),('management-current-city-snapshot-replacement-lineage:'),
      ('management-interest-snapshot-replacement-lineage:'),('management-follow-up-consent-ratio-snapshot-replacement-lineage:')) n(namespace)
    ORDER BY namespace,s.project_id,s.release_lineage_id LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(lock_key,0));
  END LOOP;

  SELECT coalesce(array_agg(contact_id ORDER BY contact_id),'{}'::text[]) INTO contact_ids
  FROM app_data.contacts WHERE workspace_id=requested_organization_workspace_id AND project_id=ANY(project_ids);
  SELECT coalesce(array_agg(promotion_target_id ORDER BY promotion_target_id),'{}'::uuid[]) INTO target_ids
  FROM app_data.promotion_targets WHERE workspace_id=requested_organization_workspace_id;
  SELECT coalesce(array_agg(questionnaire_version_id ORDER BY questionnaire_version_id),'{}'::uuid[]) INTO questionnaire_ids
  FROM app_data.questionnaire_versions WHERE project_id=ANY(project_ids);
  SELECT coalesce(array_agg(snapshot_id ORDER BY snapshot_id),'{}'::uuid[]) INTO snapshot_ids
  FROM app_private.management_report_snapshots WHERE project_id=ANY(project_ids);

  -- Fixed scope predicates and child-first order. The primary-key expression is
  -- built from pg_index for these exact relations, never from an input registry.
  FOR scope_row IN SELECT relation_name,predicate FROM unnest(relation_list,scope_predicates) scope(relation_name,predicate) LOOP
    SELECT 'jsonb_build_object(' || string_agg(format('%L,t.%I',a.attname,a.attname),',' ORDER BY k.position) || ')'
    INTO pk_expression FROM pg_index i
    CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum,position)
    JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
    WHERE i.indrelid=scope_row.relation_name::regclass AND i.indisprimary
      AND k.position<=i.indnkeyatts AND NOT a.attisdropped;
    IF pk_expression IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge primary key unavailable';
    END IF;
    FOR selected_row IN EXECUTE format('SELECT %s AS row_pk, ARRAY(SELECT field.value::uuid FROM jsonb_each_text(to_jsonb(t)) field WHERE field.key LIKE ''%%app_user_id'' AND field.value IS NOT NULL) AS user_ids FROM %s t WHERE (%s) ORDER BY %s FOR UPDATE',
      pk_expression,scope_row.relation_name,scope_row.predicate,pk_expression)
      USING requested_organization_workspace_id,project_ids,contact_ids,target_ids,questionnaire_ids,snapshot_ids,membership_ids,project_membership_ids
    LOOP
      IF EXISTS (SELECT 1 FROM unnest(selected_row.user_ids) id WHERE NOT (id=ANY(affected_user_ids))) THEN
        RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge user collection changed; rollback and retry';
      END IF;
      INSERT INTO app_private.organization_purge_delete_authorizations
        (transaction_id,backend_pid,organization_workspace_id,relation_oid,row_pk)
      VALUES(pg_current_xact_id(),pg_backend_pid(),requested_organization_workspace_id,scope_row.relation_name::regclass,selected_row.row_pk);
    END LOOP;
  END LOOP;

  -- All waiting locks have completed. One database observation governs both
  -- eligibility and the value-free completion time; no external clock is used.
  reference_time:=clock_timestamp();
  IF attempt_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
    OR attempt_row.status NOT IN ('deletion_pending','purge_due','purge_failed')
    OR attempt_row.status IS NULL OR attempt_row.restored_at_utc IS NOT NULL
    OR workspace_deleted_at IS DISTINCT FROM attempt_row.effective_at_utc
    OR attempt_row.purge_after_utc IS DISTINCT FROM attempt_row.effective_at_utc+interval '720 hours'
    OR reference_time < attempt_row.purge_after_utc
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_deletion_request_claims c
      WHERE c.request_id=expected_deletion_request_id AND c.deletion_request_id=expected_deletion_request_id
      AND c.organization_workspace_id=requested_organization_workspace_id
      AND c.effective_at_utc=attempt_row.effective_at_utc AND c.purge_after_utc=attempt_row.purge_after_utc)
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge cycle unavailable';
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.lock_rank,r.request_uuid,r.claim_family),'[]'::jsonb)
  INTO rechecked_request_set FROM (
    SELECT * FROM app_private.organization_purge_requests_v1(requested_organization_workspace_id)
    UNION SELECT 8,'organization-deletion-request','organization-deletion-request',expected_deletion_request_id
  ) r;
  IF request_set IS DISTINCT FROM rechecked_request_set THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge collection changed; rollback and retry';
  END IF;

  -- Independent anchors and no-FK references need explicit scope checks.
  -- Existing FKs reject incoming references from preserved rows on DELETE;
  -- neither mechanism expands the authorized set to satisfy a constraint.
  FOR query IN SELECT statement FROM (VALUES
    ('SELECT EXISTS (SELECT 1 FROM app_data.contacts t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.contact_attempts t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.contact_revision_conflicts t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.change_feed t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.contact_drafts t WHERE t.workspace_id=$1 OR t.project_id=ANY($2))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.personal_action_plans t WHERE t.workspace_id=$1 OR t.project_id=ANY($2))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.personal_action_reminders t WHERE t.workspace_id=$1 OR t.project_id=ANY($2))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.contact_drafts t WHERE t.questionnaire_version_id=ANY($5))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.user_current_projects t WHERE t.project_id=ANY($2))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.project_follow_up_consent_opt_in_versions t WHERE t.project_id=ANY($2))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_access_events t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.promotion_target_id=ANY($4)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.promotion_target_id=ANY($4)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships t WHERE (t.workspace_id=$1) IS DISTINCT FROM (t.person_target_id=ANY($4)) OR (t.workspace_id=$1) IS DISTINCT FROM (t.institution_target_id=ANY($4)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships t WHERE (t.promotion_target_id=ANY($4)) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_conflicts t WHERE (t.promotion_target_id=ANY($4)) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions t WHERE (t.promotion_target_id=ANY($4)) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions t JOIN app_data.promotion_target_relationship_conflicts c ON c.conflict_id=t.resolved_conflict_id WHERE t.promotion_target_id=ANY($4) AND (t.promotion_target_id IS DISTINCT FROM c.promotion_target_id OR t.project_id IS DISTINCT FROM c.project_id))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.project_memberships t WHERE (t.organization_membership_id=ANY($7)) IS DISTINCT FROM (t.project_id=ANY($2)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_creation_audit_events t LEFT JOIN app_private.organization_creation_request_claims parent_row ON parent_row.request_id=t.request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_directed_account_invitation_audit_events t LEFT JOIN app_private.organization_directed_account_invitation_request_claims parent_row ON parent_row.invitation_id=t.invitation_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_audit_events t LEFT JOIN app_private.organization_owner_transfer_request_claims parent_row ON parent_row.request_id=t.request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_membership_self_leave_audit_events t LEFT JOIN app_private.organization_membership_self_leave_request_claims parent_row ON parent_row.request_id=t.request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_shareable_join_link_audit_events t LEFT JOIN app_private.organization_shareable_join_link_request_claims parent_row ON parent_row.link_id=t.link_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_shareable_join_application_audit_events t LEFT JOIN app_private.organization_shareable_join_application_request_claims parent_row ON parent_row.application_id=t.application_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_project_membership_assignment_audit_events t LEFT JOIN app_private.organization_project_membership_assignment_request_claims parent_row ON parent_row.request_id=t.request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_deletion_audit_events t LEFT JOIN app_private.organization_deletion_request_claims deletion ON deletion.request_id=t.request_id AND t.operation=''organization-deletion-request:v1'' LEFT JOIN app_private.organization_deletion_restore_claims restoration ON restoration.request_id=t.request_id AND t.operation=''organization-deletion-restore:v1'' WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(deletion.organization_workspace_id=$1,restoration.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_creation_audit_events t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_creation_audit_events t LEFT JOIN app_data.organization_owner_assignments parent_row ON parent_row.organization_owner_assignment_id=t.organization_owner_assignment_id WHERE t.organization_owner_assignment_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_creation_request_claims t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_creation_request_claims t LEFT JOIN app_data.organization_owner_assignments parent_row ON parent_row.organization_owner_assignment_id=t.organization_owner_assignment_id WHERE t.organization_owner_assignment_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_directed_account_invitation_audit_events t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_directed_account_invitation_request_claims t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.accepted_organization_membership_id WHERE t.accepted_organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_membership_self_leave_audit_events t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_membership_self_leave_request_claims t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_audit_events t LEFT JOIN app_data.organization_owner_assignments parent_row ON parent_row.organization_owner_assignment_id=t.organization_owner_assignment_id WHERE t.organization_owner_assignment_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_audit_events t LEFT JOIN app_data.organization_owner_assignments parent_row ON parent_row.organization_owner_assignment_id=t.previous_owner_assignment_id WHERE t.previous_owner_assignment_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_request_claims t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.target_organization_membership_id WHERE t.target_organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_request_claims t LEFT JOIN app_data.organization_owner_assignments parent_row ON parent_row.organization_owner_assignment_id=t.organization_owner_assignment_id WHERE t.organization_owner_assignment_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_request_claims t LEFT JOIN app_data.organization_owner_assignments parent_row ON parent_row.organization_owner_assignment_id=t.previous_owner_assignment_id WHERE t.previous_owner_assignment_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_project_membership_assignment_audit_events t LEFT JOIN app_data.project_memberships parent_row ON parent_row.project_membership_id=t.project_membership_id WHERE t.project_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_project_membership_assignment_request_claims t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_project_membership_assignment_request_claims t LEFT JOIN app_data.project_memberships parent_row ON parent_row.project_membership_id=t.project_membership_id WHERE t.project_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_membership_id=ANY($7),false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_shareable_join_application_audit_events t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.organization_membership_id WHERE t.organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_shareable_join_application_audit_events t LEFT JOIN app_private.organization_shareable_join_link_request_claims parent_row ON parent_row.link_id=t.link_id WHERE t.link_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_shareable_join_application_request_claims t LEFT JOIN app_data.organization_memberships parent_row ON parent_row.organization_membership_id=t.approved_organization_membership_id WHERE t.approved_organization_membership_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_shareable_join_application_request_claims t LEFT JOIN app_private.organization_shareable_join_link_request_claims parent_row ON parent_row.link_id=t.link_id WHERE t.link_id IS NOT NULL AND ((t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(parent_row.organization_workspace_id=$1,false)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_project_membership_assignment_request_claims t JOIN app_data.project_memberships pm USING(project_membership_id) WHERE t.organization_workspace_id=$1 AND (t.project_id IS DISTINCT FROM pm.project_id OR t.organization_membership_id IS DISTINCT FROM pm.organization_membership_id))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_project_membership_assignment_audit_events t JOIN app_data.project_memberships pm USING(project_membership_id) WHERE t.organization_workspace_id=$1 AND t.project_id IS DISTINCT FROM pm.project_id)'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.warehouse_outbox t WHERE (t.project_id=ANY($2)) IS DISTINCT FROM (t.contact_id=ANY($3)))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.contact_attempts t JOIN app_data.contacts c ON c.contact_id=t.linked_contact_id WHERE t.workspace_id=$1 AND (t.project_id IS DISTINCT FROM c.project_id OR t.workspace_id IS DISTINCT FROM c.workspace_id))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.contact_revision_conflicts t JOIN app_data.contacts c USING(contact_id) WHERE t.workspace_id=$1 AND (t.project_id IS DISTINCT FROM c.project_id OR t.workspace_id IS DISTINCT FROM c.workspace_id OR t.app_user_id IS DISTINCT FROM c.app_user_id))'),
    ('SELECT EXISTS (SELECT 1 FROM app_data.processed_commands t JOIN app_data.change_feed f ON f.cursor_token=t.server_cursor WHERE f.workspace_id=$1 AND t.app_user_id IS DISTINCT FROM f.app_user_id)'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.management_current_city_report_snapshot_access_events t JOIN app_private.management_current_city_report_release_attempts a ON a.release_request_id=t.current_city_release_request_id WHERE t.project_id=ANY($2) AND t.project_id IS DISTINCT FROM a.project_id)'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.management_interest_report_snapshot_access_events t JOIN app_private.management_interest_report_release_attempts a ON a.release_request_id=t.interest_release_request_id WHERE t.project_id=ANY($2) AND t.project_id IS DISTINCT FROM a.project_id)'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.management_original_region_report_snapshot_access_events t JOIN app_private.management_original_region_report_release_attempts a ON a.release_request_id=t.original_region_release_request_id WHERE t.project_id=ANY($2) AND t.project_id IS DISTINCT FROM a.project_id)'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.management_follow_up_consent_report_snapshot_access_events t JOIN app_private.management_follow_up_consent_report_release_attempts a ON a.release_request_id=t.follow_up_consent_release_request_id WHERE t.project_id=ANY($2) AND t.project_id IS DISTINCT FROM a.project_id)'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.management_report_release_v2_attempts t JOIN app_private.management_report_release_attempts a ON a.release_request_id=t.delegated_release_request_id WHERE t.project_id=ANY($2) AND t.project_id IS DISTINCT FROM a.project_id)')
,
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_deletion_current t LEFT JOIN app_private.organization_deletion_request_claims c ON c.request_id=t.deletion_request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(c.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_deletion_restore_claims t LEFT JOIN app_private.organization_deletion_request_claims c ON c.request_id=t.deletion_request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(c.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_deletion_audit_events t LEFT JOIN app_private.organization_deletion_request_claims c ON c.request_id=t.deletion_request_id WHERE (t.organization_workspace_id=$1) IS DISTINCT FROM coalesce(c.organization_workspace_id=$1,false))'),
    ('SELECT EXISTS (SELECT 1 FROM app_private.organization_deletion_audit_events t LEFT JOIN app_private.organization_deletion_request_claims d ON d.request_id=t.request_id AND t.operation=''organization-deletion-request:v1'' LEFT JOIN app_private.organization_deletion_restore_claims r ON r.request_id=t.request_id AND t.operation=''organization-deletion-restore:v1'' WHERE t.organization_workspace_id=$1 AND (t.deletion_request_id IS DISTINCT FROM coalesce(d.deletion_request_id,r.deletion_request_id) OR t.occurred_at_utc IS DISTINCT FROM coalesce(d.effective_at_utc,r.restored_at_utc)))')
  ) checks(statement) LOOP
    EXECUTE query INTO cross_root
      USING requested_organization_workspace_id,project_ids,contact_ids,target_ids,questionnaire_ids,snapshot_ids,membership_ids,project_membership_ids;
    IF cross_root THEN
      RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge cross-root reference';
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(request_set) AS r(lock_rank integer,claim_family text,request_uuid uuid)
    LEFT JOIN app_private.management_report_release_request_claims claim ON claim.release_request_id=r.request_uuid
    WHERE r.lock_rank=10 AND (claim.release_request_id IS NULL OR claim.release_family_id IS DISTINCT FROM r.claim_family))
    OR EXISTS (SELECT 1 FROM app_private.management_report_snapshots snapshot
      WHERE snapshot.project_id=ANY(project_ids) AND NOT EXISTS (
        SELECT 1 FROM jsonb_to_recordset(request_set) AS r(lock_rank integer,request_uuid uuid)
        WHERE r.lock_rank=10 AND r.request_uuid=snapshot.release_request_id))
  THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge release claim provenance mismatch'; END IF;

  -- In-root references must also agree on their project, not merely belong to W.
  IF EXISTS (SELECT 1 FROM app_data.contacts c JOIN app_data.questionnaire_versions q USING(questionnaire_version_id)
    WHERE c.contact_id=ANY(contact_ids) AND c.project_id IS DISTINCT FROM q.project_id)
    OR EXISTS (SELECT 1 FROM app_data.questionnaire_drafts d LEFT JOIN app_data.questionnaire_versions source
      ON source.questionnaire_version_id=d.source_questionnaire_version_id
      LEFT JOIN app_data.questionnaire_versions published ON published.questionnaire_version_id=d.published_questionnaire_version_id
      WHERE d.project_id=ANY(project_ids) AND (source.project_id IS DISTINCT FROM d.project_id AND source.questionnaire_version_id IS NOT NULL
        OR published.project_id IS DISTINCT FROM d.project_id AND published.questionnaire_version_id IS NOT NULL))
    OR EXISTS (SELECT 1 FROM app_data.questionnaire_metric_compatibility_events e
      JOIN app_data.questionnaire_metrics m USING(questionnaire_metric_id)
      JOIN app_data.questionnaire_versions candidate ON candidate.questionnaire_version_id=e.candidate_questionnaire_version_id
      JOIN app_data.questionnaire_versions reference ON reference.questionnaire_version_id=e.reference_questionnaire_version_id
      LEFT JOIN app_data.questionnaire_metric_compatibility_events target ON target.event_id=e.target_event_id
      WHERE e.project_id=ANY(project_ids) AND (e.project_id IS DISTINCT FROM m.project_id
        OR e.project_id IS DISTINCT FROM candidate.project_id OR e.project_id IS DISTINCT FROM reference.project_id
        OR (target.event_id IS NOT NULL AND (target.project_id IS DISTINCT FROM e.project_id OR target.questionnaire_metric_id IS DISTINCT FROM e.questionnaire_metric_id))))
    OR EXISTS (SELECT 1 FROM app_data.questionnaire_metric_members member
      JOIN app_data.questionnaire_metrics metric USING(questionnaire_metric_id)
      JOIN app_data.questionnaire_versions version USING(questionnaire_version_id)
      JOIN app_data.questionnaire_metric_compatibility_events event ON event.event_id=member.source_event_id
      WHERE metric.project_id=ANY(project_ids) AND (metric.project_id IS DISTINCT FROM version.project_id
        OR metric.project_id IS DISTINCT FROM event.project_id OR metric.questionnaire_metric_id IS DISTINCT FROM event.questionnaire_metric_id))
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links link JOIN app_data.contacts contact USING(contact_id)
      WHERE contact.contact_id=ANY(contact_ids) AND NOT EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships relation
        WHERE relation.promotion_target_id=link.promotion_target_id AND relation.project_id=contact.project_id))
    OR EXISTS (SELECT 1 FROM app_data.warehouse_outbox outbox LEFT JOIN app_data.contacts contact USING(contact_id)
      WHERE outbox.project_id=ANY(project_ids) AND (contact.contact_id IS NULL OR contact.project_id IS DISTINCT FROM outbox.project_id))
    OR EXISTS (SELECT 1 FROM app_data.questionnaire_publish_requests receipt
      JOIN app_data.questionnaire_drafts draft USING(questionnaire_draft_id)
      JOIN app_data.questionnaire_versions version USING(questionnaire_version_id)
      WHERE version.project_id=ANY(project_ids) AND (version.project_id IS DISTINCT FROM draft.project_id
        OR draft.published_questionnaire_version_id IS DISTINCT FROM version.questionnaire_version_id))
    OR EXISTS (SELECT 1 FROM app_data.questionnaire_metric_members member
      JOIN app_data.questionnaire_metric_compatibility_events event ON event.event_id=member.source_event_id
      WHERE event.project_id=ANY(project_ids) AND ((member.membership_role='origin' AND (event.reference_questionnaire_version_id IS DISTINCT FROM member.questionnaire_version_id
        OR event.reference_question_id IS DISTINCT FROM member.question_id)) OR (member.membership_role='compatible' AND (event.candidate_questionnaire_version_id IS DISTINCT FROM member.questionnaire_version_id
        OR event.candidate_question_id IS DISTINCT FROM member.question_id))))
  THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge project provenance mismatch'; END IF;

  -- Report provenance checks use only the fixed reporting relations above.
  FOREACH query IN ARRAY relation_list LOOP
    IF (query LIKE 'app_private.management_%' AND query <> 'app_private.management_report_release_request_claims')
      OR query IN ('app_private.deidentified_location_anomaly_access_events','app_data.management_analysis_current_contexts') THEN
      EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s t WHERE t.project_id=ANY($1) AND (
        (to_jsonb(t) ? ''organization_workspace_id'' AND (to_jsonb(t)->>''organization_workspace_id'')::uuid IS DISTINCT FROM $2)
        OR (to_jsonb(t) ? ''project_membership_id'' AND NOT EXISTS (SELECT 1 FROM app_data.project_memberships pm
          WHERE pm.project_membership_id=(to_jsonb(t)->>''project_membership_id'')::uuid AND pm.project_id=t.project_id
          AND pm.organization_membership_id=(to_jsonb(t)->>''organization_membership_id'')::uuid))
        OR (to_jsonb(t) ? ''organization_membership_id'' AND NOT EXISTS (SELECT 1 FROM app_data.organization_memberships om
          WHERE om.organization_membership_id=(to_jsonb(t)->>''organization_membership_id'')::uuid AND om.organization_workspace_id=$2
          AND om.app_user_id=coalesce(to_jsonb(t)->>''requested_by_app_user_id'',to_jsonb(t)->>''app_user_id'')::uuid))
        OR EXISTS (SELECT 1 FROM (VALUES (''capability_grant_id''),(''view_capability_grant_id''),(''export_capability_grant_id'')) grant_key(name)
          JOIN app_data.management_report_capability_grants g ON g.capability_grant_id=(to_jsonb(t)->>grant_key.name)::uuid
          WHERE g.project_membership_id IS DISTINCT FROM (to_jsonb(t)->>''project_membership_id'')::uuid)
        OR EXISTS (SELECT 1 FROM (VALUES (''previous_snapshot_id''),(''compared_snapshot_id''),(''released_snapshot_id''),
          (''superseded_snapshot_id''),(''replacement_snapshot_id''),(''resolved_snapshot_id'')) key(name)
          JOIN app_private.management_report_snapshots snapshot ON snapshot.snapshot_id=(to_jsonb(t)->>key.name)::uuid
          WHERE snapshot.project_id IS DISTINCT FROM t.project_id)))',query)
      INTO cross_root USING project_ids,requested_organization_workspace_id;
      IF cross_root THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge report provenance mismatch'; END IF;
    END IF;
  END LOOP;

  UPDATE app_private.organization_deletion_current SET status='purging'
  WHERE organization_workspace_id=requested_organization_workspace_id;
  SET CONSTRAINTS app_data.workspaces_active_owner_invariant,
    app_data.organization_memberships_active_owner_invariant,
    app_data.organization_owner_assignments_active_owner_invariant DEFERRED;

  INSERT INTO app_private.organization_purge_request_tombstones(claim_family,request_uuid,purge_completed_at_utc)
  SELECT r.claim_family,r.request_uuid,reference_time
  FROM jsonb_to_recordset(request_set) AS r(lock_rank integer,lock_namespace text,claim_family text,request_uuid uuid);
  INSERT INTO app_private.organization_creation_request_tombstones(claim_family,request_id)
  SELECT 'organization-creation:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-creation-request' ON CONFLICT DO NOTHING;
  INSERT INTO app_private.organization_directed_account_invitation_request_tombstones(claim_family,invitation_id)
  SELECT 'organization-directed-account-invitation:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-directed-account-invitation-request' ON CONFLICT DO NOTHING;
  INSERT INTO app_private.organization_owner_transfer_request_tombstones(claim_family,request_id)
  SELECT 'organization-owner-transfer:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-owner-transfer-request' ON CONFLICT DO NOTHING;
  INSERT INTO app_private.organization_membership_self_leave_request_tombstones(claim_family,request_id)
  SELECT 'organization-membership-self-leave:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-membership-self-leave-request' ON CONFLICT DO NOTHING;
  INSERT INTO app_private.organization_shareable_join_link_request_tombstones(claim_family,link_id)
  SELECT 'organization-shareable-join-link:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-shareable-join-link-request' ON CONFLICT DO NOTHING;
  INSERT INTO app_private.organization_shareable_join_application_request_tombstones(claim_family,application_id)
  SELECT 'organization-shareable-join-application:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-shareable-join-application-request' ON CONFLICT DO NOTHING;
  INSERT INTO app_private.organization_project_membership_assignment_request_tombstones(claim_family,request_id)
  SELECT 'organization-project-membership-assignment:v1',r.request_uuid FROM jsonb_to_recordset(request_set) AS r(claim_family text,request_uuid uuid)
  WHERE r.claim_family='organization-project-membership-assignment-request' ON CONFLICT DO NOTHING;

  -- Authorization was frozen from exact locked rows before any delete. Runtime
  -- deletion therefore cannot expand through a now-changing join or cascade.
  FOREACH query IN ARRAY relation_list LOOP
    LOOP
      lock_key:='';
      IF query='app_data.questionnaire_metric_compatibility_events' THEN
        lock_key:=' AND NOT EXISTS (SELECT 1 FROM app_data.questionnaire_metric_compatibility_events child WHERE child.target_event_id=t.event_id)';
      ELSIF query='app_private.management_report_snapshots' THEN
        lock_key:=' AND NOT EXISTS (SELECT 1 FROM app_private.management_report_snapshots child WHERE child.previous_snapshot_id=t.snapshot_id)';
      END IF;
      EXECUTE format('DELETE FROM %s t USING app_private.organization_purge_delete_authorizations a
        WHERE a.transaction_id=pg_current_xact_id() AND a.backend_pid=pg_backend_pid()
          AND a.organization_workspace_id=$1 AND a.relation_oid=$2 AND to_jsonb(t) @> a.row_pk%s',query,lock_key)
      USING requested_organization_workspace_id,query::regclass;
      GET DIAGNOSTICS deleted_count=ROW_COUNT;
      IF lock_key='' OR deleted_count=0 THEN EXIT; END IF;
    END LOOP;
    EXECUTE format('SELECT count(*) FROM %s t JOIN app_private.organization_purge_delete_authorizations a
      ON to_jsonb(t) @> a.row_pk WHERE a.transaction_id=pg_current_xact_id() AND a.backend_pid=pg_backend_pid()
      AND a.organization_workspace_id=$1 AND a.relation_oid=$2',query)
    INTO remaining_count USING requested_organization_workspace_id,query::regclass;
    IF remaining_count<>0 THEN
      RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge selected rows remain';
    END IF;
  END LOOP;
  SET CONSTRAINTS app_data.workspaces_active_owner_invariant,
    app_data.organization_memberships_active_owner_invariant,
    app_data.organization_owner_assignments_active_owner_invariant IMMEDIATE;
  DELETE FROM app_private.organization_purge_delete_authorizations
  WHERE transaction_id=pg_current_xact_id() AND backend_pid=pg_backend_pid()
    AND organization_workspace_id=requested_organization_workspace_id;
  RETURN QUERY SELECT expected_deletion_request_id,reference_time;
END
$function$;

-- Caller must ROLLBACK the complete failed purge transaction and begin a new
-- transaction before this call. No exception text or business payload is stored.
CREATE FUNCTION app_private.record_organization_purge_failed_v1(
  requested_organization_workspace_id uuid,
  expected_deletion_request_id uuid
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  attempt_row app_private.organization_deletion_current%ROWTYPE;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  reference_time timestamptz;
BEGIN
  IF requested_organization_workspace_id IS NULL OR expected_deletion_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid organization purge failure request';
  END IF;
  IF current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge failure requires read committed';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('organization-deletion-request:' || expected_deletion_request_id::text,0));
  PERFORM app_private.lock_organization_governance_v1(requested_organization_workspace_id);
  SELECT w.workspace_kind,w.deleted_at INTO workspace_kind,workspace_deleted_at
  FROM app_data.workspaces w WHERE w.workspace_id=requested_organization_workspace_id FOR UPDATE;
  SELECT a.* INTO attempt_row FROM app_private.organization_deletion_current a
  WHERE a.organization_workspace_id=requested_organization_workspace_id FOR UPDATE;
  reference_time:=clock_timestamp();
  IF workspace_kind IS DISTINCT FROM 'organization'
    OR attempt_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
    OR attempt_row.status IS NULL OR attempt_row.status NOT IN ('deletion_pending','purge_due','purge_failed')
    OR attempt_row.restored_at_utc IS NOT NULL
    OR workspace_deleted_at IS DISTINCT FROM attempt_row.effective_at_utc
    OR attempt_row.purge_after_utc IS DISTINCT FROM attempt_row.effective_at_utc+interval '720 hours'
    OR reference_time<attempt_row.purge_after_utc
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_deletion_request_claims c
      WHERE c.request_id=expected_deletion_request_id AND c.deletion_request_id=expected_deletion_request_id
      AND c.organization_workspace_id=requested_organization_workspace_id
      AND c.effective_at_utc=attempt_row.effective_at_utc AND c.purge_after_utc=attempt_row.purge_after_utc)
    OR app_private.organization_purge_request_completed_v1('organization-deletion-request',expected_deletion_request_id)
  THEN RETURN false; END IF;
  UPDATE app_private.organization_deletion_current SET status='purge_failed'
  WHERE organization_workspace_id=requested_organization_workspace_id;
  RETURN true;
END
$function$;

REVOKE ALL ON FUNCTION app_private.organization_purge_requests_v1(uuid),
  app_private.finalize_organization_purge_v1(uuid,uuid),
  app_private.record_organization_purge_failed_v1(uuid,uuid)
FROM PUBLIC,tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; trusted_role oid; relation_row record;
BEGIN
  SELECT proowner,pg_get_userbyid(proowner) INTO STRICT trusted_role,trusted_owner FROM pg_proc
  WHERE oid='app_private.validate_organization_membership_v1()'::regprocedure;
  IF NOT has_table_privilege(trusted_role,'app_data.app_users','SELECT')
    OR NOT has_table_privilege(trusted_role,'app_data.app_users','UPDATE')
    OR EXISTS (SELECT 1 FROM pg_class c WHERE c.oid='app_data.app_users'::regclass AND c.relrowsecurity
      AND NOT EXISTS (SELECT 1 FROM pg_roles r WHERE r.oid=trusted_role AND (r.rolsuper OR r.rolbypassrls))
      AND NOT (c.relowner=trusted_role AND NOT c.relforcerowsecurity))
  THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge user lock privileges unavailable'; END IF;
  EXECUTE format('ALTER FUNCTION app_private.organization_purge_requests_v1(uuid) OWNER TO %I',trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.finalize_organization_purge_v1(uuid,uuid) OWNER TO %I',trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.record_organization_purge_failed_v1(uuid,uuid) OWNER TO %I',trusted_owner);
  -- Verify the existing trusted owner can see/delete every fixed relation. Do not
  -- silently introduce a bypass role, a public policy or a runtime table grant.
  FOR relation_row IN SELECT c.oid,c.relowner,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c
    WHERE c.oid IN (SELECT unnest(ARRAY[
      'app_data.change_feed'::regclass,
      'app_data.contact_answers'::regclass,
      'app_data.contact_attempts'::regclass,
      'app_data.contact_audit_events'::regclass,
      'app_data.contact_region_assignments'::regclass,
      'app_data.contact_revision_conflicts'::regclass,
      'app_data.contact_target_links'::regclass,
      'app_data.management_analysis_current_contexts'::regclass,
      'app_data.organization_owner_assignments'::regclass,
      'app_data.processed_commands'::regclass,
      'app_data.promotion_target_access_events'::regclass,
      'app_data.promotion_target_assignments'::regclass,
      'app_data.promotion_target_creation_requests'::regclass,
      'app_data.promotion_target_institution_relation_revisions'::regclass,
      'app_data.promotion_target_relationship_conflict_resolutions'::regclass,
      'app_data.promotion_target_relationship_revisions'::regclass,
      'app_data.promotion_target_retention_events'::regclass,
      'app_data.promotion_target_retention_policies'::regclass,
      'app_data.promotion_target_stage_aliases'::regclass,
      'app_data.questionnaire_metric_members'::regclass,
      'app_data.questionnaire_options'::regclass,
      'app_data.questionnaire_publish_requests'::regclass,
      'app_data.warehouse_outbox'::regclass,
      'app_private.deidentified_location_anomaly_access_events'::regclass,
      'app_private.deidentified_location_anomaly_ids'::regclass,
      'app_private.management_current_city_report_snapshot_access_events'::regclass,
      'app_private.management_current_city_report_snapshot_directory_access_events'::regclass,
      'app_private.management_current_city_report_snapshot_replacements'::regclass,
      'app_private.management_follow_up_consent_opt_in_versions'::regclass,
      'app_private.management_follow_up_consent_ratio_report_snapshot_replacements'::regclass,
      'app_private.management_follow_up_consent_report_snapshot_access_events'::regclass,
      'app_private.management_follow_up_consent_snapshot_directory_access_events'::regclass,
      'app_private.management_interest_report_snapshot_access_events'::regclass,
      'app_private.management_interest_report_snapshot_directory_access_events'::regclass,
      'app_private.management_interest_report_snapshot_replacements'::regclass,
      'app_private.management_original_region_report_snapshot_access_events'::regclass,
      'app_private.management_original_region_report_snapshot_replacements'::regclass,
      'app_private.management_original_region_snapshot_directory_access_events'::regclass,
      'app_private.management_report_release_request_claims'::regclass,
      'app_private.management_report_release_v2_attempts'::regclass,
      'app_private.management_report_snapshot_access_events'::regclass,
      'app_private.management_report_snapshot_directory_access_events'::regclass,
      'app_private.management_report_snapshot_export_events'::regclass,
      'app_private.management_report_snapshot_replacements'::regclass,
      'app_private.organization_creation_audit_events'::regclass,
      'app_private.organization_creation_request_claims'::regclass,
      'app_private.organization_deletion_audit_events'::regclass,
      'app_private.organization_deletion_request_claims'::regclass,
      'app_private.organization_deletion_restore_claims'::regclass,
      'app_private.organization_directed_account_invitation_audit_events'::regclass,
      'app_private.organization_directed_account_invitation_request_claims'::regclass,
      'app_private.organization_membership_self_leave_audit_events'::regclass,
      'app_private.organization_membership_self_leave_request_claims'::regclass,
      'app_private.organization_owner_transfer_audit_events'::regclass,
      'app_private.organization_owner_transfer_request_claims'::regclass,
      'app_private.organization_project_membership_assignment_audit_events'::regclass,
      'app_private.organization_project_membership_assignment_request_claims'::regclass,
      'app_private.organization_shareable_join_application_audit_events'::regclass,
      'app_private.organization_shareable_join_application_request_claims'::regclass,
      'app_private.organization_shareable_join_link_audit_events'::regclass,
      'app_private.organization_shareable_join_link_request_claims'::regclass,
      'app_data.contact_location_provenance'::regclass,
      'app_data.promotion_target_institution_relationships'::regclass,
      'app_data.promotion_target_relationship_conflicts'::regclass,
      'app_data.questionnaire_drafts'::regclass,
      'app_data.questionnaire_metric_compatibility_events'::regclass,
      'app_private.management_current_city_report_release_attempts'::regclass,
      'app_private.management_follow_up_consent_report_release_attempts'::regclass,
      'app_private.management_interest_report_release_attempts'::regclass,
      'app_private.management_original_region_report_release_attempts'::regclass,
      'app_private.management_report_release_attempts'::regclass,
      'app_data.contact_revisions'::regclass,
      'app_data.management_report_capability_grants'::regclass,
      'app_data.promotion_target_project_relationships'::regclass,
      'app_data.questionnaire_metrics'::regclass,
      'app_data.questionnaire_questions'::regclass,
      'app_private.management_report_snapshots'::regclass,
      'app_private.project_reporting_time_zone_versions'::regclass,
      'app_data.contacts'::regclass,
      'app_data.project_memberships'::regclass,
      'app_data.promotion_targets'::regclass,
      'app_data.organization_memberships'::regclass,
      'app_data.questionnaire_versions'::regclass,
      'app_data.projects'::regclass,
      'app_data.workspaces'::regclass,
      'app_private.organization_deletion_current'::regclass
    ])) LOOP
    IF NOT has_table_privilege(trusted_role,relation_row.oid,'SELECT')
      OR NOT has_table_privilege(trusted_role,relation_row.oid,'DELETE')
      OR NOT has_table_privilege(trusted_role,relation_row.oid,'UPDATE')
      OR (relation_row.relrowsecurity AND NOT EXISTS (SELECT 1 FROM pg_roles r
          WHERE r.oid=trusted_role AND (r.rolsuper OR r.rolbypassrls))
        AND NOT (relation_row.relowner=trusted_role AND NOT relation_row.relforcerowsecurity)
        AND NOT EXISTS (SELECT 1 FROM pg_policy policy WHERE policy.polrelid=relation_row.oid
          AND policy.polcmd='*' AND policy.polpermissive AND pg_get_expr(policy.polqual,policy.polrelid)='true'
          AND NOT EXISTS (SELECT 1 FROM pg_policy restrictive WHERE restrictive.polrelid=policy.polrelid
            AND NOT restrictive.polpermissive AND restrictive.polcmd IN ('*','r','d')
            AND pg_get_expr(restrictive.polqual,restrictive.polrelid) IS DISTINCT FROM 'true')
          AND (trusted_role=ANY(policy.polroles) OR EXISTS (SELECT 1 FROM unnest(policy.polroles) role_id
            WHERE role_id<>0 AND pg_has_role(trusted_role,role_id,'USAGE')))))
    THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge trusted owner privileges unavailable'; END IF;
  END LOOP;
  FOR relation_row IN SELECT c.oid,c.relowner,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c
    WHERE c.oid=ANY(ARRAY['app_data.contact_drafts'::regclass,'app_data.personal_action_plans'::regclass,'app_data.personal_action_reminders'::regclass,'app_data.user_current_projects'::regclass,'app_private.project_follow_up_consent_opt_in_versions'::regclass]) LOOP
    IF NOT has_table_privilege(trusted_role,relation_row.oid,'SELECT')
      OR (relation_row.relrowsecurity AND NOT EXISTS (SELECT 1 FROM pg_roles r WHERE r.oid=trusted_role AND (r.rolsuper OR r.rolbypassrls))
        AND NOT (relation_row.relowner=trusted_role AND NOT relation_row.relforcerowsecurity)
        AND NOT EXISTS (SELECT 1 FROM pg_policy policy WHERE policy.polrelid=relation_row.oid
          AND policy.polcmd IN ('*','r') AND policy.polpermissive AND pg_get_expr(policy.polqual,policy.polrelid)='true'
          AND NOT EXISTS (SELECT 1 FROM pg_policy restrictive WHERE restrictive.polrelid=policy.polrelid
            AND NOT restrictive.polpermissive AND restrictive.polcmd IN ('*','r')
            AND pg_get_expr(restrictive.polqual,restrictive.polrelid) IS DISTINCT FROM 'true')
          AND (trusted_role=ANY(policy.polroles) OR EXISTS (SELECT 1 FROM unnest(policy.polroles) role_id
            WHERE role_id<>0 AND pg_has_role(trusted_role,role_id,'USAGE')))))
    THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge preserved-root visibility unavailable'; END IF;
  END LOOP;
END
$owner$;
COMMENT ON FUNCTION app_private.finalize_organization_purge_v1(uuid,uuid)
IS 'Atomic trusted organization purge. Terminal retry confirms only request completion; value-free tombstones cannot revalidate a deleted workspace binding. No runtime/HTTP/scheduler grant.';
COMMENT ON FUNCTION app_private.record_organization_purge_failed_v1(uuid,uuid)
IS 'Call in a new transaction after full purge rollback; record only a still-current expired purge_failed state, without error payload.';
