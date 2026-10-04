\set ON_ERROR_STOP on
BEGIN;

-- Reviewed Slice 7DC inventory, grounded in migrations through 0104.
-- This is a structural definition baseline, not proof of runtime purge behavior.
-- Workspaces and projects are shared roots: process rows only when their workspace
-- is an organization; personal spaces and cross-organization shared roots survive.
-- RESTRICT/NO ACTION means the finalizer must explicitly order child cleanup;
-- CASCADE is still reviewed; SET NULL is not permission to retain business payload.
-- pg_constraint.confdeltype codes: a=NO ACTION, c=CASCADE, d=SET DEFAULT,
-- n=SET NULL, r=RESTRICT. Each row is child -> referenced parent.
-- Process org-owned business/report rows; preserve app_users, personal spaces,
-- and any cross-organization shared root referenced by those rows.
CREATE TEMP TABLE purge_inventory_expected_fk (
  child_relation text NOT NULL,
  constraint_name text NOT NULL,
  parent_relation text NOT NULL,
  delete_action "char" NOT NULL,
  definition text NOT NULL,
  PRIMARY KEY (child_relation, constraint_name)
);
INSERT INTO purge_inventory_expected_fk VALUES
  ('app_data.change_feed', 'change_feed_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.change_feed', 'change_feed_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.change_feed', 'change_feed_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.contact_answers', 'contact_answers_contact_id_revision_number_fkey', 'app_data.contact_revisions', 'r', 'FOREIGN KEY (contact_id, revision_number) REFERENCES app_data.contact_revisions(contact_id, revision_number) ON DELETE RESTRICT'),
  ('app_data.contact_attempts', 'contact_attempts_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.contact_attempts', 'contact_attempts_linked_contact_id_fkey', 'app_data.contacts', 'r', 'FOREIGN KEY (linked_contact_id) REFERENCES app_data.contacts(contact_id) ON DELETE RESTRICT'),
  ('app_data.contact_attempts', 'contact_attempts_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.contact_attempts', 'contact_attempts_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.contact_drafts', 'contact_drafts_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.contact_drafts', 'contact_drafts_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.contact_drafts', 'contact_drafts_questionnaire_version_id_fkey', 'app_data.questionnaire_versions', 'r', 'FOREIGN KEY (questionnaire_version_id) REFERENCES app_data.questionnaire_versions(questionnaire_version_id) ON DELETE RESTRICT'),
  ('app_data.contact_drafts', 'contact_drafts_upgrade_source_owner_fk', 'app_data.contact_drafts', 'r', 'FOREIGN KEY (app_user_id, upgraded_from_draft_id) REFERENCES app_data.contact_drafts(app_user_id, draft_id) ON DELETE RESTRICT DEFERRABLE'),
  ('app_data.contact_drafts', 'contact_drafts_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.contact_location_provenance', 'contact_location_provenance_region_fk', 'app_data.canonical_region_versions', 'r', 'FOREIGN KEY (smallest_region_id, region_tree_version) REFERENCES app_data.canonical_region_versions(region_id, tree_version) ON DELETE RESTRICT'),
  ('app_data.contact_location_provenance', 'contact_location_provenance_release_fk', 'app_data.canonical_region_tree_releases', 'r', 'FOREIGN KEY (region_tree_version) REFERENCES app_data.canonical_region_tree_releases(tree_version) ON DELETE RESTRICT'),
  ('app_data.contact_location_provenance', 'contact_location_provenance_revision_fk', 'app_data.contact_revisions', 'r', 'FOREIGN KEY (contact_id, revision_number) REFERENCES app_data.contact_revisions(contact_id, revision_number) ON DELETE RESTRICT'),
  ('app_data.contact_region_assignments', 'contact_region_assignments_contact_id_fkey', 'app_data.contacts', 'r', 'FOREIGN KEY (contact_id) REFERENCES app_data.contacts(contact_id) ON DELETE RESTRICT'),
  ('app_data.contact_region_assignments', 'contact_region_assignments_region_id_tree_version_fkey', 'app_data.canonical_region_versions', 'r', 'FOREIGN KEY (region_id, tree_version) REFERENCES app_data.canonical_region_versions(region_id, tree_version) ON DELETE RESTRICT'),
  ('app_data.contact_revision_conflicts', 'contact_revision_conflicts_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.contact_revision_conflicts', 'contact_revision_conflicts_contact_id_fkey', 'app_data.contacts', 'r', 'FOREIGN KEY (contact_id) REFERENCES app_data.contacts(contact_id) ON DELETE RESTRICT'),
  ('app_data.contact_revision_conflicts', 'contact_revision_conflicts_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.contact_revision_conflicts', 'contact_revision_conflicts_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.contact_revisions', 'contact_revisions_contact_id_fkey', 'app_data.contacts', 'r', 'FOREIGN KEY (contact_id) REFERENCES app_data.contacts(contact_id) ON DELETE RESTRICT'),
  ('app_data.contact_revisions', 'contact_revisions_revised_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (revised_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.contact_target_links', 'contact_target_links_contact_id_fkey', 'app_data.contacts', 'r', 'FOREIGN KEY (contact_id) REFERENCES app_data.contacts(contact_id) ON DELETE RESTRICT'),
  ('app_data.contact_target_links', 'contact_target_links_contact_id_revision_number_fkey', 'app_data.contact_revisions', 'r', 'FOREIGN KEY (contact_id, revision_number) REFERENCES app_data.contact_revisions(contact_id, revision_number) ON DELETE RESTRICT'),
  ('app_data.contact_target_links', 'contact_target_links_promotion_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (promotion_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.contacts', 'contacts_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.contacts', 'contacts_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.contacts', 'contacts_questionnaire_version_id_fkey', 'app_data.questionnaire_versions', 'r', 'FOREIGN KEY (questionnaire_version_id) REFERENCES app_data.questionnaire_versions(questionnaire_version_id) ON DELETE RESTRICT'),
  ('app_data.contacts', 'contacts_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.management_analysis_current_contexts', 'management_analysis_current_con_organization_membership_id_fkey', 'app_data.organization_memberships', 'r', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id) ON DELETE RESTRICT'),
  ('app_data.management_analysis_current_contexts', 'management_analysis_current_cont_organization_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.management_analysis_current_contexts', 'management_analysis_current_contexts_app_user_id_fkey', 'app_data.app_users', 'c', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE CASCADE'),
  ('app_data.management_analysis_current_contexts', 'management_analysis_current_contexts_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'r', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id) ON DELETE RESTRICT'),
  ('app_data.management_analysis_current_contexts', 'management_analysis_current_contexts_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.management_analysis_current_contexts', 'management_analysis_current_contexts_project_membership_id_fkey', 'app_data.project_memberships', 'r', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id) ON DELETE RESTRICT'),
  ('app_data.management_report_capability_grants', 'management_report_capability_grants_project_membership_id_fkey', 'app_data.project_memberships', 'r', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id) ON DELETE RESTRICT'),
  ('app_data.organization_memberships', 'organization_memberships_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.organization_memberships', 'organization_memberships_organization_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.organization_owner_assignments', 'organization_owner_assignments_organization_membership_id_fkey', 'app_data.organization_memberships', 'r', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_plan_versions', 'personal_action_plan_versions_plan_id_fkey', 'app_data.personal_action_plans', 'r', 'FOREIGN KEY (plan_id) REFERENCES app_data.personal_action_plans(plan_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_plans', 'personal_action_plans_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_plans', 'personal_action_plans_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_plans', 'personal_action_plans_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_reminder_versions', 'personal_action_reminder_versions_reminder_id_fkey', 'app_data.personal_action_reminders', 'r', 'FOREIGN KEY (reminder_id) REFERENCES app_data.personal_action_reminders(reminder_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_reminders', 'personal_action_reminders_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_reminders', 'personal_action_reminders_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.personal_action_reminders', 'personal_action_reminders_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.project_memberships', 'project_memberships_organization_membership_id_fkey', 'app_data.organization_memberships', 'r', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id) ON DELETE RESTRICT'),
  ('app_data.project_memberships', 'project_memberships_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.projects', 'projects_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_access_events', 'promotion_target_access_events_actor_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (actor_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_access_events', 'promotion_target_access_events_promotion_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (promotion_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_access_events', 'promotion_target_access_events_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_assignments', 'promotion_target_assignments_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_assignments', 'promotion_target_assignments_assigned_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (assigned_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_assignments', 'promotion_target_assignments_promotion_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (promotion_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_creation_requests', 'promotion_target_creation_requests_actor_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (actor_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_creation_requests', 'promotion_target_creation_requests_promotion_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (promotion_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relation_revisions', 'promotion_target_institution_relati_changed_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (changed_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relation_revisions', 'promotion_target_institution_relation_revi_relationship_id_fkey', 'app_data.promotion_target_institution_relationships', 'r', 'FOREIGN KEY (relationship_id) REFERENCES app_data.promotion_target_institution_relationships(relationship_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relationships', 'promotion_target_institution_relati_created_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (created_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relationships', 'promotion_target_institution_relati_updated_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (updated_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relationships', 'promotion_target_institution_relatio_institution_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (institution_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relationships', 'promotion_target_institution_relationship_person_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (person_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_institution_relationships', 'promotion_target_institution_relationships_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_project_relationships', 'promotion_target_project_relati_established_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (established_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_project_relationships', 'promotion_target_project_relationsh_updated_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (updated_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_project_relationships', 'promotion_target_project_relationships_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_project_relationships', 'promotion_target_project_relationships_promotion_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (promotion_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_conflict_resolutions', 'promotion_target_relationship_conf_resolved_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (resolved_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_conflict_resolutions', 'promotion_target_relationship_conflict_resolut_conflict_id_fkey', 'app_data.promotion_target_relationship_conflicts', 'r', 'FOREIGN KEY (conflict_id) REFERENCES app_data.promotion_target_relationship_conflicts(conflict_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_conflicts', 'promotion_target_relationshi_promotion_target_id_project__fkey1', 'app_data.promotion_target_project_relationships', 'r', 'FOREIGN KEY (promotion_target_id, project_id) REFERENCES app_data.promotion_target_project_relationships(promotion_target_id, project_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_conflicts', 'promotion_target_relationship_confl_created_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (created_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_revisions', 'promotion_target_relationship_promotion_target_id_project__fkey', 'app_data.promotion_target_project_relationships', 'r', 'FOREIGN KEY (promotion_target_id, project_id) REFERENCES app_data.promotion_target_project_relationships(promotion_target_id, project_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_revisions', 'promotion_target_relationship_revis_changed_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (changed_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_relationship_revisions', 'promotion_target_relationship_revisio_resolved_conflict_id_fkey', 'app_data.promotion_target_relationship_conflicts', 'r', 'FOREIGN KEY (resolved_conflict_id) REFERENCES app_data.promotion_target_relationship_conflicts(conflict_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_retention_events', 'promotion_target_retention_events_actor_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (actor_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_retention_events', 'promotion_target_retention_events_promotion_target_id_fkey', 'app_data.promotion_targets', 'r', 'FOREIGN KEY (promotion_target_id) REFERENCES app_data.promotion_targets(promotion_target_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_retention_events', 'promotion_target_retention_events_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_retention_policies', 'promotion_target_retention_policies_updated_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (updated_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_retention_policies', 'promotion_target_retention_policies_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_stage_aliases', 'promotion_target_stage_aliases_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.promotion_target_stage_aliases', 'promotion_target_stage_aliases_updated_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (updated_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_targets', 'promotion_targets_created_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (created_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.promotion_targets', 'promotion_targets_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_drafts', 'questionnaire_drafts_created_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (created_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_drafts', 'questionnaire_drafts_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_drafts', 'questionnaire_drafts_published_questionnaire_version_id_fkey', 'app_data.questionnaire_versions', 'r', 'FOREIGN KEY (published_questionnaire_version_id) REFERENCES app_data.questionnaire_versions(questionnaire_version_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_drafts', 'questionnaire_drafts_source_questionnaire_version_id_fkey', 'app_data.questionnaire_versions', 'r', 'FOREIGN KEY (source_questionnaire_version_id) REFERENCES app_data.questionnaire_versions(questionnaire_version_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_drafts', 'questionnaire_drafts_updated_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (updated_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_compatibility_events', 'questionnaire_metric_compatib_candidate_questionnaire_vers_fkey', 'app_data.questionnaire_questions', 'r', 'FOREIGN KEY (candidate_questionnaire_version_id, candidate_question_id) REFERENCES app_data.questionnaire_questions(questionnaire_version_id, question_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_compatibility_events', 'questionnaire_metric_compatib_reference_questionnaire_vers_fkey', 'app_data.questionnaire_questions', 'r', 'FOREIGN KEY (reference_questionnaire_version_id, reference_question_id) REFERENCES app_data.questionnaire_questions(questionnaire_version_id, question_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_compatibility_events', 'questionnaire_metric_compatibility_event_actor_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (actor_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_compatibility_events', 'questionnaire_metric_compatibility_events_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_compatibility_events', 'questionnaire_metric_compatibility_events_target_event_id_fkey', 'app_data.questionnaire_metric_compatibility_events', 'r', 'FOREIGN KEY (target_event_id) REFERENCES app_data.questionnaire_metric_compatibility_events(event_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_compatibility_events', 'questionnaire_metric_compatibility_questionnaire_metric_id_fkey', 'app_data.questionnaire_metrics', 'r', 'FOREIGN KEY (questionnaire_metric_id) REFERENCES app_data.questionnaire_metrics(questionnaire_metric_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_members', 'questionnaire_metric_members_questionnaire_metric_id_fkey', 'app_data.questionnaire_metrics', 'r', 'FOREIGN KEY (questionnaire_metric_id) REFERENCES app_data.questionnaire_metrics(questionnaire_metric_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_members', 'questionnaire_metric_members_questionnaire_version_id_ques_fkey', 'app_data.questionnaire_questions', 'r', 'FOREIGN KEY (questionnaire_version_id, question_id) REFERENCES app_data.questionnaire_questions(questionnaire_version_id, question_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metric_members', 'questionnaire_metric_members_source_event_id_fkey', 'app_data.questionnaire_metric_compatibility_events', 'r', 'FOREIGN KEY (source_event_id) REFERENCES app_data.questionnaire_metric_compatibility_events(event_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metrics', 'questionnaire_metrics_created_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (created_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_metrics', 'questionnaire_metrics_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_options', 'questionnaire_options_questionnaire_version_id_question_id_fkey', 'app_data.questionnaire_questions', 'r', 'FOREIGN KEY (questionnaire_version_id, question_id) REFERENCES app_data.questionnaire_questions(questionnaire_version_id, question_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_publish_requests', 'questionnaire_publish_requests_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_publish_requests', 'questionnaire_publish_requests_questionnaire_draft_id_fkey', 'app_data.questionnaire_drafts', 'r', 'FOREIGN KEY (questionnaire_draft_id) REFERENCES app_data.questionnaire_drafts(questionnaire_draft_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_publish_requests', 'questionnaire_publish_requests_questionnaire_version_id_fkey', 'app_data.questionnaire_versions', 'r', 'FOREIGN KEY (questionnaire_version_id) REFERENCES app_data.questionnaire_versions(questionnaire_version_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_questions', 'questionnaire_questions_questionnaire_version_id_fkey', 'app_data.questionnaire_versions', 'r', 'FOREIGN KEY (questionnaire_version_id) REFERENCES app_data.questionnaire_versions(questionnaire_version_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_versions', 'questionnaire_versions_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.questionnaire_versions', 'questionnaire_versions_published_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (published_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_data.user_current_projects', 'user_current_projects_app_user_id_fkey', 'app_data.app_users', 'c', 'FOREIGN KEY (app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE CASCADE'),
  ('app_data.user_current_projects', 'user_current_projects_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.warehouse_outbox', 'warehouse_outbox_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_data.workspaces', 'workspaces_personal_owner_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (personal_owner_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_private.deidentified_location_anomaly_access_events', 'deidentified_location_anomaly_a_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.deidentified_location_anomaly_access_events', 'deidentified_location_anomaly_ac_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.deidentified_location_anomaly_access_events', 'deidentified_location_anomaly_acc_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.deidentified_location_anomaly_access_events', 'deidentified_location_anomaly_access_e_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.deidentified_location_anomaly_access_events', 'deidentified_location_anomaly_access_events_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.deidentified_location_anomaly_access_events', 'deidentified_location_anomaly_access_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.deidentified_location_anomaly_ids', 'deidentified_location_anomaly_ids_source_id_fkey', 'app_data.contact_location_provenance', 'r', 'FOREIGN KEY (source_id) REFERENCES app_data.contact_location_provenance(source_id) ON DELETE RESTRICT'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_repor_project_id_reporting_time_zo_fkey', 'app_private.project_reporting_time_zone_versions', 'a', 'FOREIGN KEY (project_id, reporting_time_zone_version_number) REFERENCES app_private.project_reporting_time_zone_versions(project_id, version_number)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report__organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_r_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_re_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_relea_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_releas_compared_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (compared_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_releas_released_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (released_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_release_attempts_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_current_city_report_release_attempts', 'management_current_city_report_release_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_repor_current_city_release_request_fkey', 'app_private.management_current_city_report_release_attempts', 'a', 'FOREIGN KEY (current_city_release_request_id) REFERENCES app_private.management_current_city_report_release_attempts(release_request_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_organization_membership_id_fkey1', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_s_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_sn_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_snaps_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_snapsh_resolved_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (resolved_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_snapsho_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_current_city_report_snapshot_access_events', 'management_current_city_report_snapshot_access__project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_current_city_report_snapshot_directory_access_events', 'management_current_city_report__organization_workspace_id_fkey1', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_current_city_report_snapshot_directory_access_events', 'management_current_city_report_organization_membership_id_fkey2', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_current_city_report_snapshot_directory_access_events', 'management_current_city_report_s_requested_by_app_user_id_fkey1', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_current_city_report_snapshot_directory_access_events', 'management_current_city_report_snap_project_membership_id_fkey1', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_current_city_report_snapshot_directory_access_events', 'management_current_city_report_snapsh_capability_grant_id_fkey1', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_current_city_report_snapshot_directory_access_events', 'management_current_city_report_snapshot_directo_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report__organization_workspace_id_fkey2', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_organization_membership_id_fkey3', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_s_requested_by_app_user_id_fkey2', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_sna_replacement_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (replacement_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_snap_project_membership_id_fkey2', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_snap_superseded_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (superseded_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_snapsh_capability_grant_id_fkey2', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_current_city_report_snapshot_replacements', 'management_current_city_report_snapshot_replace_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_follow_up_consent_opt_in_versions', 'management_follow_up_consent_op_organization_membership_id_fkey', 'app_data.organization_memberships', 'r', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id) ON DELETE RESTRICT'),
  ('app_private.management_follow_up_consent_opt_in_versions', 'management_follow_up_consent_opt__requested_by_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_private.management_follow_up_consent_opt_in_versions', 'management_follow_up_consent_opt_in__project_membership_id_fkey', 'app_data.project_memberships', 'r', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id) ON DELETE RESTRICT'),
  ('app_private.management_follow_up_consent_opt_in_versions', 'management_follow_up_consent_opt_in_ve_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'r', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id) ON DELETE RESTRICT'),
  ('app_private.management_follow_up_consent_opt_in_versions', 'management_follow_up_consent_opt_in_versions_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_private.management_follow_up_consent_opt_in_versions', 'management_follow_up_consent_opt_organization_workspace_id_fkey', 'app_data.workspaces', 'r', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id) ON DELETE RESTRICT'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_ra_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_rat_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_rati_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_ratio__superseded_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (superseded_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_ratio_r_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_ratio_rep_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_ratio_replacement_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (replacement_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements', 'management_follow_up_consent_ratio_report_snaps_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent__project_id_reporting_time_zo_fkey', 'app_private.project_reporting_time_zone_versions', 'a', 'FOREIGN KEY (project_id, reporting_time_zone_version_number) REFERENCES app_private.project_reporting_time_zone_versions(project_id, version_number)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_re_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_rep_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_repo_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_report__project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_report_r_compared_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (compared_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_report_r_released_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (released_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_report_re_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_follow_up_consent_report_release_attempts', 'management_follow_up_consent_report_release_att_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent__follow_up_consent_release_re_fkey', 'app_private.management_follow_up_consent_report_release_attempts', 'a', 'FOREIGN KEY (follow_up_consent_release_request_id) REFERENCES app_private.management_follow_up_consent_report_release_attempts(release_request_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_r_organization_membership_id_fkey1', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_re_organization_workspace_id_fkey1', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_rep_requested_by_app_user_id_fkey1', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_report_project_membership_id_fkey1', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_report_s_previous_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (previous_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_report_s_resolved_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (resolved_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_report_sn_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_follow_up_consent_report_snapshot_access_events', 'management_follow_up_consent_report_snapshot_ac_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_follow_up_consent_snapshot_directory_access_events', 'management_follow_up_consent_sn_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_follow_up_consent_snapshot_directory_access_events', 'management_follow_up_consent_sna_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_follow_up_consent_snapshot_directory_access_events', 'management_follow_up_consent_snap_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_follow_up_consent_snapshot_directory_access_events', 'management_follow_up_consent_snapsho_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_follow_up_consent_snapshot_directory_access_events', 'management_follow_up_consent_snapshot__capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_follow_up_consent_snapshot_directory_access_events', 'management_follow_up_consent_snapshot_directory_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_re_project_id_reporting_time_zo_fkey', 'app_private.project_reporting_time_zone_versions', 'a', 'FOREIGN KEY (project_id, reporting_time_zone_version_number) REFERENCES app_private.project_reporting_time_zone_versions(project_id, version_number)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_rele_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_relea_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_releas_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_release_a_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_release_at_compared_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (compared_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_release_at_released_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (released_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_release_att_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_interest_report_release_attempts', 'management_interest_report_release_attempts_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_sna_interest_release_request_id_fkey', 'app_private.management_interest_report_release_attempts', 'a', 'FOREIGN KEY (interest_release_request_id) REFERENCES app_private.management_interest_report_release_attempts(release_request_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snap_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snaps_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snapsh_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snapshot__project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snapshot_a_resolved_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (resolved_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snapshot_ac_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_interest_report_snapshot_access_events', 'management_interest_report_snapshot_access_even_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_interest_report_snapshot_directory_access_events', 'management_interest_report_sna_organization_membership_id_fkey1', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_interest_report_snapshot_directory_access_events', 'management_interest_report_snap_organization_workspace_id_fkey1', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_interest_report_snapshot_directory_access_events', 'management_interest_report_snaps_requested_by_app_user_id_fkey1', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_interest_report_snapshot_directory_access_events', 'management_interest_report_snapshot_di_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_interest_report_snapshot_directory_access_events', 'management_interest_report_snapshot_directory_a_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_interest_report_snapshot_directory_access_events', 'management_interest_report_snapshot_project_membership_id_fkey1', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_sna_organization_membership_id_fkey2', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snap_organization_workspace_id_fkey2', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snaps_requested_by_app_user_id_fkey2', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snapsho_replacement_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (replacement_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snapshot_project_membership_id_fkey2', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snapshot_re_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snapshot_replacement_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_interest_report_snapshot_replacements', 'management_interest_report_snapshot_superseded_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (superseded_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_re_project_id_reporting_time_zo_fkey', 'app_private.project_reporting_time_zone_versions', 'a', 'FOREIGN KEY (project_id, reporting_time_zone_version_number) REFERENCES app_private.project_reporting_time_zone_versions(project_id, version_number)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_repo_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_repor_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_report_re_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_report_rel_compared_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (compared_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_report_rel_released_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (released_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_report_rele_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_report_release_attem_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_original_region_report_release_attempts', 'management_original_region_report_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_re_original_region_release_requ_fkey', 'app_private.management_original_region_report_release_attempts', 'a', 'FOREIGN KEY (original_region_release_request_id) REFERENCES app_private.management_original_region_report_release_attempts(release_request_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_rep_organization_membership_id_fkey1', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_repo_organization_workspace_id_fkey1', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_repor_requested_by_app_user_id_fkey1', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_report_sn_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_report_sna_resolved_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (resolved_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_report_snap_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_original_region_report_snapshot_access_events', 'management_original_region_report_snapshot_acce_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_rep_organization_membership_id_fkey2', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_repo_organization_workspace_id_fkey2', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_repor_requested_by_app_user_id_fkey2', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_report__replacement_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (replacement_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_report_s_project_membership_id_fkey1', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_report_s_superseded_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (superseded_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_report_sna_capability_grant_id_fkey1', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_original_region_report_snapshot_replacements', 'management_original_region_report_snapshot_repl_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_original_region_snapshot_directory_access_events', 'management_original_region_snap_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_original_region_snapshot_directory_access_events', 'management_original_region_snaps_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_original_region_snapshot_directory_access_events', 'management_original_region_snapsh_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_original_region_snapshot_directory_access_events', 'management_original_region_snapshot__project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_original_region_snapshot_directory_access_events', 'management_original_region_snapshot_di_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_original_region_snapshot_directory_access_events', 'management_original_region_snapshot_directory_a_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_release_attempts', 'management_report_release_attempt_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_release_attempts', 'management_report_release_attempts_compared_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (compared_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_release_attempts', 'management_report_release_attempts_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_release_attempts', 'management_report_release_attempts_released_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (released_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2__delegated_release_request_id_fkey', 'app_private.management_report_release_attempts', 'a', 'FOREIGN KEY (delegated_release_request_id) REFERENCES app_private.management_report_release_attempts(release_request_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2__project_id_reporting_time_zo_fkey', 'app_private.project_reporting_time_zone_versions', 'a', 'FOREIGN KEY (project_id, reporting_time_zone_version_number) REFERENCES app_private.project_reporting_time_zone_versions(project_id, version_number)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_at_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_att_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_atte_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_attempt_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_attempts_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_attempts_compared_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (compared_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_attempts_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_release_v2_attempts', 'management_report_release_v2_attempts_released_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (released_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_acce_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_acces_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_access_ev_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_access_eve_resolved_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (resolved_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_access_even_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_access_events_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_snapshot_access_events', 'management_report_snapshot_access_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_snapshot_directory_access_events', 'management_report_snapshot_dire_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_report_snapshot_directory_access_events', 'management_report_snapshot_direc_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_report_snapshot_directory_access_events', 'management_report_snapshot_direct_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_snapshot_directory_access_events', 'management_report_snapshot_directory_a_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_report_snapshot_directory_access_events', 'management_report_snapshot_directory_access_eve_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_snapshot_directory_access_events', 'management_report_snapshot_directory_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_expo_export_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (export_capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_expo_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_expor_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_export_ev_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_export_eve_resolved_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (resolved_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_export_events_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_export_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_snapshot_export_events', 'management_report_snapshot_export_view_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (view_capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_repl_organization_membership_id_fkey', 'app_data.organization_memberships', 'a', 'FOREIGN KEY (organization_membership_id) REFERENCES app_data.organization_memberships(organization_membership_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_repla_organization_workspace_id_fkey', 'app_data.workspaces', 'a', 'FOREIGN KEY (organization_workspace_id) REFERENCES app_data.workspaces(workspace_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_replac_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_replace_replacement_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (replacement_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_replacem_superseded_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (superseded_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_replaceme_project_membership_id_fkey', 'app_data.project_memberships', 'a', 'FOREIGN KEY (project_membership_id) REFERENCES app_data.project_memberships(project_membership_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_replacement_capability_grant_id_fkey', 'app_data.management_report_capability_grants', 'a', 'FOREIGN KEY (capability_grant_id) REFERENCES app_data.management_report_capability_grants(capability_grant_id)'),
  ('app_private.management_report_snapshot_replacements', 'management_report_snapshot_replacements_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.management_report_snapshots', 'management_report_snapshots_created_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (created_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.management_report_snapshots', 'management_report_snapshots_previous_snapshot_id_fkey', 'app_private.management_report_snapshots', 'a', 'FOREIGN KEY (previous_snapshot_id) REFERENCES app_private.management_report_snapshots(snapshot_id)'),
  ('app_private.management_report_snapshots', 'management_report_snapshots_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)'),
  ('app_private.project_follow_up_consent_opt_in_versions', 'project_follow_up_consent_opt_in_version_actor_app_user_id_fkey', 'app_data.app_users', 'r', 'FOREIGN KEY (actor_app_user_id) REFERENCES app_data.app_users(app_user_id) ON DELETE RESTRICT'),
  ('app_private.project_follow_up_consent_opt_in_versions', 'project_follow_up_consent_opt_in_versions_project_id_fkey', 'app_data.projects', 'r', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id) ON DELETE RESTRICT'),
  ('app_private.project_reporting_time_zone_versions', 'project_reporting_time_zone_versi_requested_by_app_user_id_fkey', 'app_data.app_users', 'a', 'FOREIGN KEY (requested_by_app_user_id) REFERENCES app_data.app_users(app_user_id)'),
  ('app_private.project_reporting_time_zone_versions', 'project_reporting_time_zone_versions_project_id_fkey', 'app_data.projects', 'a', 'FOREIGN KEY (project_id) REFERENCES app_data.projects(project_id)');

CREATE TEMP TABLE purge_inventory_expected_family (relation_name text PRIMARY KEY);
INSERT INTO purge_inventory_expected_family VALUES
  ('app_private.organization_creation_request_claims'),
  ('app_private.organization_creation_request_tombstones'),
  ('app_private.organization_creation_audit_events'),
  ('app_private.organization_directed_account_invitation_request_claims'),
  ('app_private.organization_directed_account_invitation_request_tombstones'),
  ('app_private.organization_directed_account_invitation_audit_events'),
  ('app_private.organization_owner_transfer_request_claims'),
  ('app_private.organization_owner_transfer_request_tombstones'),
  ('app_private.organization_owner_transfer_audit_events'),
  ('app_private.organization_membership_self_leave_request_claims'),
  ('app_private.organization_membership_self_leave_request_tombstones'),
  ('app_private.organization_membership_self_leave_audit_events'),
  ('app_private.organization_shareable_join_link_request_claims'),
  ('app_private.organization_shareable_join_link_request_tombstones'),
  ('app_private.organization_shareable_join_link_audit_events'),
  ('app_private.organization_shareable_join_application_request_claims'),
  ('app_private.organization_shareable_join_application_request_tombstones'),
  ('app_private.organization_shareable_join_application_audit_events'),
  ('app_private.organization_project_membership_assignment_request_claims'),
  ('app_private.organization_project_membership_assignment_request_tombstones'),
  ('app_private.organization_project_membership_assignment_audit_events'),
  ('app_private.organization_deletion_current'),
  ('app_private.organization_deletion_request_claims'),
  ('app_private.organization_deletion_restore_claims'),
  ('app_private.organization_deletion_audit_events');

CREATE TEMP TABLE purge_inventory_expected_trigger (
  relation_name text NOT NULL, trigger_name text NOT NULL,
  function_identity text NOT NULL, function_definition_md5 text NOT NULL,
  trigger_type integer NOT NULL, enabled_state "char" NOT NULL,
  PRIMARY KEY (relation_name, trigger_name)
);
INSERT INTO purge_inventory_expected_trigger VALUES
  ('app_data.organization_owner_assignments', 'organization_owner_assignments_active_owner_invariant', 'app_private.enforce_organization_active_owner_v1()', '8c8e7db05f022b936c6fa92c3ac9873a', 29, 'O'),
  ('app_data.organization_owner_assignments', 'organization_owner_assignments_governance_fence', 'app_private.lock_organization_governance_for_mutation_v1()', '1e53de6f759226f46d02da4060d03810', 31, 'O'),
  ('app_data.organization_owner_assignments', 'organization_owner_assignments_protect_history', 'app_private.protect_organization_owner_assignment_history_v1()', '34324c840ea3d2adbf5a975846f7dba8', 27, 'O'),
  ('app_data.organization_owner_assignments', 'organization_owner_assignments_validate', 'app_private.validate_organization_owner_assignment_v1()', '0ad0bc74b6bb44f04409e1dc29584239', 23, 'O'),
  ('app_private.organization_creation_audit_events', 'organization_creation_audit_events_immutable', 'app_private.protect_organization_creation_audit_event_v1()', 'c30d7f3d1e68739fe9e2436ba4770b8a', 27, 'O'),
  ('app_private.organization_creation_request_claims', 'organization_creation_request_claims_immutable', 'app_private.protect_organization_creation_request_claim_v1()', '61bbb7da4bb9ae5aa9b43316288a0e68', 27, 'O'),
  ('app_private.organization_creation_request_tombstones', 'organization_creation_request_tombstones_immutable', 'app_private.protect_organization_creation_request_tombstone_v1()', 'f46bf594f281be9806be475c91b28163', 27, 'O'),
  ('app_private.organization_deletion_audit_events', 'organization_deletion_audit_events_immutable', 'app_private.protect_organization_deletion_audit_v1()', '4a673fd0dd4714563c26bae4bcf6628d', 27, 'O'),
  ('app_private.organization_deletion_request_claims', 'organization_deletion_request_claims_immutable', 'app_private.protect_organization_deletion_claim_v1()', 'c25f07378dd1a229da2fa217a70d22fd', 27, 'O'),
  ('app_private.organization_deletion_restore_claims', 'organization_deletion_restore_claims_immutable', 'app_private.protect_organization_deletion_claim_v1()', 'c25f07378dd1a229da2fa217a70d22fd', 27, 'O'),
  ('app_private.organization_directed_account_invitation_audit_events', 'organization_directed_invitation_audit_events_immutable', 'app_private.protect_organization_directed_invitation_audit_event_v1()', 'be2f699fb3451c0c87ad867376ba63c5', 27, 'O'),
  ('app_private.organization_directed_account_invitation_request_claims', 'organization_directed_invitation_claims_immutable', 'app_private.protect_organization_directed_invitation_claim_v1()', '77ed0a84b16d6161c2436b9dc9635703', 27, 'O'),
  ('app_private.organization_directed_account_invitation_request_tombstones', 'organization_directed_invitation_tombstones_immutable', 'app_private.protect_organization_directed_invitation_tombstone_v1()', '7faf324b761ef7f413148695fbaaf1fc', 27, 'O'),
  ('app_private.organization_membership_self_leave_audit_events', 'organization_membership_self_leave_audit_events_immutable', 'app_private.protect_organization_membership_self_leave_audit_event_v1()', 'fcc9092bb77a0e44d72e3f94ee512268', 27, 'O'),
  ('app_private.organization_membership_self_leave_request_claims', 'organization_membership_self_leave_claims_immutable', 'app_private.protect_organization_membership_self_leave_request_claim_v1()', '605210a4ba44115a2747b19c51b9895e', 27, 'O'),
  ('app_private.organization_membership_self_leave_request_tombstones', 'organization_membership_self_leave_tombstones_immutable', 'app_private.protect_organization_membership_self_leave_request_tombstone_v1()', 'c0cd4989fa1bc1d3c9e441a33d3a9f71', 27, 'O'),
  ('app_private.organization_owner_transfer_audit_events', 'organization_owner_transfer_audit_events_immutable', 'app_private.protect_organization_owner_transfer_audit_event_v1()', '19375ff8dafbaf502fe248df810b83c6', 27, 'O'),
  ('app_private.organization_owner_transfer_request_claims', 'organization_owner_transfer_request_claims_immutable', 'app_private.protect_organization_owner_transfer_request_claim_v1()', '618dfe00d3bd10dcb378c82f5a6d0532', 27, 'O'),
  ('app_private.organization_owner_transfer_request_tombstones', 'organization_owner_transfer_request_tombstones_immutable', 'app_private.protect_organization_owner_transfer_request_tombstone_v1()', 'aac5356f40144c5c20ca9c94a1d5cc77', 27, 'O'),
  ('app_private.organization_project_membership_assignment_audit_events', 'organization_project_membership_assignment_audit_immutable', 'app_private.protect_organization_project_membership_assignment_terminal_v1()', '843cf9a8eeaa7d220a2aea1366ad095e', 27, 'O'),
  ('app_private.organization_project_membership_assignment_request_claims', 'organization_project_membership_assignment_claims_immutable', 'app_private.protect_organization_project_membership_assignment_claim_v1()', '5cc0061cb0781b656f58d0de57a438ba', 27, 'O'),
  ('app_private.organization_project_membership_assignment_request_tombstones', 'organization_project_membership_assignment_tombstones_immutable', 'app_private.protect_organization_project_membership_assignment_terminal_v1()', '843cf9a8eeaa7d220a2aea1366ad095e', 27, 'O'),
  ('app_private.organization_shareable_join_application_audit_events', 'organization_shareable_join_application_audit_events_immutable', 'app_private.protect_organization_shareable_join_application_audit_event_v1()', 'a851e466ccfd99478ff93632afe622a5', 27, 'O'),
  ('app_private.organization_shareable_join_application_request_claims', 'organization_shareable_join_application_claims_immutable', 'app_private.protect_organization_shareable_join_application_claim_v1()', '006b52b1494113545a1fae67fe3e38c5', 27, 'O'),
  ('app_private.organization_shareable_join_application_request_tombstones', 'organization_shareable_join_application_tombstones_immutable', 'app_private.protect_organization_shareable_join_application_tombstone_v1()', '2050fa5b3a437d33346ce0f727744f92', 27, 'O'),
  ('app_private.organization_shareable_join_link_audit_events', 'organization_shareable_join_link_audit_events_immutable', 'app_private.protect_organization_shareable_join_link_audit_event_v1()', 'aa428eb76c2110ce00a0d02e8ddce7c0', 27, 'O'),
  ('app_private.organization_shareable_join_link_request_claims', 'organization_shareable_join_link_claims_immutable', 'app_private.protect_organization_shareable_join_link_claim_v1()', '04e90c62f2b5deafc0bc3a095bfd4c60', 27, 'O'),
  ('app_private.organization_shareable_join_link_request_tombstones', 'organization_shareable_join_link_tombstones_immutable', 'app_private.protect_organization_shareable_join_link_tombstone_v1()', '32f8e4cc9ac772679ce4fca74ec52566', 27, 'O');

-- Definition fingerprints bind each trigger to its qualified guard implementation.
CREATE TEMP VIEW purge_inventory_actual_trigger AS
SELECT n.nspname || '.' || c.relname AS relation_name, t.tgname AS trigger_name,
       pn.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS function_identity,
       md5(pg_get_functiondef(p.oid)) AS function_definition_md5,
       t.tgtype AS trigger_type, t.tgenabled AS enabled_state
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace pn ON pn.oid=p.pronamespace
WHERE NOT t.tgisinternal AND (
  (n.nspname='app_private' AND
    (c.relname ~ '^organization_.*_(claims|tombstones|audit_events)$'
     OR c.relname='organization_deletion_current'))
  OR (n.nspname='app_data' AND c.relname='organization_owner_assignments')
);

DO $inventory$
DECLARE
  difference_count integer;
BEGIN
  IF EXISTS (
    (SELECT relation_name FROM purge_inventory_expected_family
     EXCEPT
     SELECT 'app_private.' || c.relname
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='app_private'
       AND (c.relname ~ '^organization_.*_(claims|tombstones|audit_events)$'
         OR c.relname='organization_deletion_current'))
    UNION ALL
    (SELECT 'app_private.' || c.relname
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='app_private'
       AND (c.relname ~ '^organization_.*_(claims|tombstones|audit_events)$'
         OR c.relname='organization_deletion_current')
     EXCEPT
     SELECT relation_name FROM purge_inventory_expected_family)
  ) THEN
    RAISE EXCEPTION 'organization claim/audit/tombstone family inventory drift';
  END IF;

  IF EXISTS (
    (SELECT relation_name, trigger_name, function_identity,
            function_definition_md5, trigger_type, enabled_state
     FROM purge_inventory_expected_trigger
     EXCEPT SELECT * FROM purge_inventory_actual_trigger)
    UNION ALL
    (SELECT * FROM purge_inventory_actual_trigger
     EXCEPT SELECT relation_name, trigger_name, function_identity,
                   function_definition_md5, trigger_type, enabled_state
     FROM purge_inventory_expected_trigger)
  ) THEN
    RAISE EXCEPTION 'organization immutable trigger inventory drift';
  END IF;

  WITH RECURSIVE roots(relid) AS (
    VALUES
      ('app_data.workspaces'::regclass),
      ('app_data.projects'::regclass),
      ('app_data.organization_memberships'::regclass),
      ('app_data.organization_owner_assignments'::regclass),
      ('app_data.project_memberships'::regclass),
      ('app_data.management_report_capability_grants'::regclass),
      ('app_private.management_report_snapshots'::regclass),
      ('app_private.management_report_snapshot_replacements'::regclass),
      ('app_private.management_interest_report_snapshot_replacements'::regclass),
      ('app_private.management_original_region_report_snapshot_replacements'::regclass),
      ('app_private.management_current_city_report_snapshot_replacements'::regclass),
      ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements'::regclass),
      ('app_private.management_report_release_attempts'::regclass),
      ('app_private.management_report_release_v2_attempts'::regclass),
      ('app_private.management_interest_report_release_attempts'::regclass),
      ('app_private.management_original_region_report_release_attempts'::regclass),
      ('app_private.management_current_city_report_release_attempts'::regclass),
      ('app_private.management_follow_up_consent_report_release_attempts'::regclass)
  ), scope(relid) AS (
    SELECT relid FROM roots
    UNION
    SELECT c.conrelid FROM pg_constraint c JOIN scope s ON c.confrelid=s.relid
    WHERE c.contype='f'
  ), actual_fk AS (
    SELECT child_ns.nspname || '.' || child.relname AS child_relation,
      con.conname AS constraint_name,
      parent_ns.nspname || '.' || parent.relname AS parent_relation,
      con.confdeltype AS delete_action,
      pg_get_constraintdef(con.oid) AS definition
    FROM pg_constraint con
    JOIN pg_class child ON child.oid=con.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
    JOIN pg_class parent ON parent.oid=con.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
    WHERE con.contype='f'
      AND (con.conrelid IN (SELECT relid FROM scope)
        OR con.confrelid IN (SELECT relid FROM scope))
  ), drift AS (
    (SELECT * FROM purge_inventory_expected_fk EXCEPT SELECT * FROM actual_fk)
    UNION ALL
    (SELECT * FROM actual_fk EXCEPT SELECT * FROM purge_inventory_expected_fk)
  )
  SELECT count(*) INTO difference_count FROM drift;
  IF difference_count <> 0 THEN
    RAISE EXCEPTION 'organization purge FK inventory drift (% unmatched rows)', difference_count;
  END IF;
END
$inventory$;

-- Negative trigger probes are transactional and the final ROLLBACK restores both.
ALTER TABLE app_data.organization_owner_assignments
  DISABLE TRIGGER organization_owner_assignments_protect_history;
DO $disabled_guard$
BEGIN
  IF NOT EXISTS (
    (SELECT relation_name, trigger_name, function_identity,
            function_definition_md5, trigger_type, enabled_state
     FROM purge_inventory_expected_trigger
     EXCEPT SELECT * FROM purge_inventory_actual_trigger)
    UNION ALL
    (SELECT * FROM purge_inventory_actual_trigger
     EXCEPT SELECT relation_name, trigger_name, function_identity,
                   function_definition_md5, trigger_type, enabled_state
     FROM purge_inventory_expected_trigger)
  ) THEN
    RAISE EXCEPTION 'disabled immutable trigger escaped inventory comparison';
  END IF;
END
$disabled_guard$;
ALTER TABLE app_data.organization_owner_assignments
  ENABLE TRIGGER organization_owner_assignments_protect_history;

CREATE OR REPLACE FUNCTION app_private.protect_organization_owner_assignment_history_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $replacement$
BEGIN
  RETURN NEW;
END
$replacement$;
DO $replaced_guard$
BEGIN
  IF NOT EXISTS (
    (SELECT relation_name, trigger_name, function_identity,
            function_definition_md5, trigger_type, enabled_state
     FROM purge_inventory_expected_trigger
     EXCEPT SELECT * FROM purge_inventory_actual_trigger)
    UNION ALL
    (SELECT * FROM purge_inventory_actual_trigger
     EXCEPT SELECT relation_name, trigger_name, function_identity,
                   function_definition_md5, trigger_type, enabled_state
     FROM purge_inventory_expected_trigger)
  ) THEN
    RAISE EXCEPTION 'replaced guard function escaped definition fingerprint comparison';
  END IF;
END
$replaced_guard$;

-- Prove the same catalog comparison rejects an unreviewed child FK without
-- leaving a schema object: the synthetic table lives only in this psql session.
CREATE TABLE app_private.organization_purge_inventory_negative_probe (
  workspace_id uuid REFERENCES app_data.workspaces(workspace_id)
);
DO $negative$
DECLARE
  difference_count integer;
BEGIN
  WITH RECURSIVE roots(relid) AS (
    VALUES
      ('app_data.workspaces'::regclass), ('app_data.projects'::regclass),
      ('app_data.organization_memberships'::regclass),
      ('app_data.organization_owner_assignments'::regclass),
      ('app_data.project_memberships'::regclass),
      ('app_data.management_report_capability_grants'::regclass),
      ('app_private.management_report_snapshots'::regclass),
      ('app_private.management_report_snapshot_replacements'::regclass),
      ('app_private.management_interest_report_snapshot_replacements'::regclass),
      ('app_private.management_original_region_report_snapshot_replacements'::regclass),
      ('app_private.management_current_city_report_snapshot_replacements'::regclass),
      ('app_private.management_follow_up_consent_ratio_report_snapshot_replacements'::regclass),
      ('app_private.management_report_release_attempts'::regclass),
      ('app_private.management_report_release_v2_attempts'::regclass),
      ('app_private.management_interest_report_release_attempts'::regclass),
      ('app_private.management_original_region_report_release_attempts'::regclass),
      ('app_private.management_current_city_report_release_attempts'::regclass),
      ('app_private.management_follow_up_consent_report_release_attempts'::regclass)
  ), scope(relid) AS (
    SELECT relid FROM roots
    UNION
    SELECT c.conrelid FROM pg_constraint c JOIN scope s ON c.confrelid=s.relid
    WHERE c.contype='f'
  ), actual_fk AS (
    SELECT child_ns.nspname || '.' || child.relname AS child_relation,
      con.conname AS constraint_name,
      parent_ns.nspname || '.' || parent.relname AS parent_relation,
      con.confdeltype AS delete_action,
      pg_get_constraintdef(con.oid) AS definition
    FROM pg_constraint con
    JOIN pg_class child ON child.oid=con.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
    JOIN pg_class parent ON parent.oid=con.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
    WHERE con.contype='f'
      AND (con.conrelid IN (SELECT relid FROM scope)
        OR con.confrelid IN (SELECT relid FROM scope))
  ), drift AS (
    (SELECT * FROM purge_inventory_expected_fk EXCEPT SELECT * FROM actual_fk)
    UNION ALL
    (SELECT * FROM actual_fk EXCEPT SELECT * FROM purge_inventory_expected_fk)
  )
  SELECT count(*) INTO difference_count FROM drift;
  IF difference_count = 0 THEN
    RAISE EXCEPTION 'synthetic unreviewed FK was not rejected by the inventory comparison';
  END IF;
END
$negative$;
DROP TABLE app_private.organization_purge_inventory_negative_probe;

SELECT 'organization purge dependency inventory: passed' AS result;
ROLLBACK;
