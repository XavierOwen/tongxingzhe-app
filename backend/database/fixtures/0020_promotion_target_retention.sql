\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE retention_owner_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-retention.example.test',
  'retention-owner'
);

CREATE TEMP TABLE retention_intruder_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-retention.example.test',
  'retention-intruder'
);

CREATE TEMP TABLE retention_manual_target AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  'person', '待撤回对象', '+1 312 555 0199', 'withdraw@example.test',
  'retention-manual-target'
);

CREATE TEMP TABLE retention_institution AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  'institution', '保留期机构', NULL, NULL,
  'retention-institution'
);

CREATE TEMP TABLE retention_expired_target AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  'person', '应自动匿名化', NULL, NULL,
  'retention-expired-target'
);

CREATE TEMP TABLE retention_review_target AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  'person', '即将复核对象', NULL, NULL,
  'retention-review-target'
);

CREATE TEMP TABLE retention_institution_relation AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
  (SELECT (target->>'target_id')::uuid FROM retention_institution),
  'employment_representative',
  '含敏感职务说明',
  'retention-institution-relation'
);

DO $policy_checks$
BEGIN
  IF app_data.configure_promotion_target_retention_policy(
    (SELECT app_user_id FROM retention_owner_context),
    (SELECT workspace_id FROM retention_owner_context),
    (SELECT project_id FROM retention_owner_context),
    6
  ) <> 6 OR app_data.configure_promotion_target_retention_policy(
    (SELECT app_user_id FROM retention_owner_context),
    (SELECT workspace_id FROM retention_owner_context),
    (SELECT project_id FROM retention_owner_context),
    12
  ) <> 12 THEN
    RAISE EXCEPTION 'shorter retention policy was not stored';
  END IF;
  BEGIN
    PERFORM app_data.configure_promotion_target_retention_policy(
      (SELECT app_user_id FROM retention_owner_context),
      (SELECT workspace_id FROM retention_owner_context),
      (SELECT project_id FROM retention_owner_context),
      13
    );
    RAISE EXCEPTION 'retention period above 12 months was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END
$policy_checks$;

RESET ROLE;

INSERT INTO app_data.promotion_target_project_relationships (
  promotion_target_id,
  project_id,
  current_stage,
  current_follow_up_note,
  established_by_app_user_id
) VALUES (
  (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
  (SELECT project_id FROM retention_owner_context),
  2,
  '含敏感共享备注',
  (SELECT app_user_id FROM retention_owner_context)
);

INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  channel,
  location_kind,
  reach_count,
  interest_level
) VALUES (
  'retention-contact-fact',
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  (SELECT questionnaire_version_id FROM retention_owner_context),
  clock_timestamp() - interval '1 month',
  'America/Chicago',
  'voice_call',
  'not_applicable',
  3,
  2
);

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  snapshot
) VALUES (
  'retention-contact-fact',
  1,
  (SELECT app_user_id FROM retention_owner_context),
  '{}'::jsonb
);

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
) VALUES (
  'retention-contact-fact',
  1,
  (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
  2,
  'unknown',
  false,
  true
);

UPDATE app_data.promotion_targets
SET created_at = clock_timestamp() - interval '13 months'
WHERE promotion_target_id = (
  SELECT (target->>'target_id')::uuid FROM retention_expired_target
);

UPDATE app_data.promotion_targets
SET created_at = clock_timestamp() - interval '11 months 15 days'
WHERE promotion_target_id = (
  SELECT (target->>'target_id')::uuid FROM retention_review_target
);

SET LOCAL ROLE tongxingzhe_runtime;

DO $late_renewal_check$
BEGIN
  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      (SELECT app_user_id FROM retention_owner_context),
      (SELECT workspace_id FROM retention_owner_context),
      (SELECT project_id FROM retention_owner_context),
      (SELECT (target->>'target_id')::uuid FROM retention_expired_target),
      'renew',
      'purpose_confirmed',
      'retention-late-renewal'
    );
    RAISE EXCEPTION 'renewal after the due time was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END
$late_renewal_check$;

CREATE TEMP TABLE retention_tasks AS
SELECT task FROM app_data.list_promotion_target_retention_tasks(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context)
);

DO $task_checks$
BEGIN
  IF (SELECT count(*) FROM retention_tasks) <> 1
    OR (SELECT task->>'target_id' FROM retention_tasks) <>
      (SELECT target->>'target_id' FROM retention_review_target)
    OR EXISTS (
      SELECT 1 FROM retention_tasks
      WHERE task ?| ARRAY['display_name', 'phone', 'email']
    )
  THEN
    RAISE EXCEPTION 'retention task is not generic or due sweep failed';
  END IF;
END
$task_checks$;

CREATE TEMP TABLE retention_renewal AS
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  (SELECT (target->>'target_id')::uuid FROM retention_review_target),
  'renew',
  'purpose_confirmed',
  'retention-renewal-1'
);

CREATE TEMP TABLE retention_renewal_replay AS
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  (SELECT (target->>'target_id')::uuid FROM retention_review_target),
  'renew',
  'purpose_confirmed',
  'retention-renewal-1'
);

DO $retention_rejections$
BEGIN
  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      (SELECT app_user_id FROM retention_owner_context),
      (SELECT workspace_id FROM retention_owner_context),
      (SELECT project_id FROM retention_owner_context),
      (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
      'anonymize',
      'retention_expired',
      'retention-too-early'
    );
    RAISE EXCEPTION 'early retention expiry was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      (SELECT app_user_id FROM retention_intruder_context),
      (SELECT workspace_id FROM retention_intruder_context),
      (SELECT project_id FROM retention_intruder_context),
      (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
      'anonymize',
      'withdrawal',
      'retention-intruder-attempt'
    );
    RAISE EXCEPTION 'cross-workspace anonymization was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$retention_rejections$;

CREATE TEMP TABLE retention_anonymized AS
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
  'anonymize',
  'withdrawal',
  'retention-withdrawal-1'
);

CREATE TEMP TABLE retention_anonymized_replay AS
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM retention_owner_context),
  (SELECT workspace_id FROM retention_owner_context),
  (SELECT project_id FROM retention_owner_context),
  (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
  'anonymize',
  'withdrawal',
  'retention-withdrawal-1'
);

DO $replay_rewrite_check$
BEGIN
  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      (SELECT app_user_id FROM retention_owner_context),
      (SELECT workspace_id FROM retention_owner_context),
      (SELECT project_id FROM retention_owner_context),
      (SELECT (target->>'target_id')::uuid FROM retention_manual_target),
      'renew',
      'purpose_confirmed',
      'retention-withdrawal-1'
    );
    RAISE EXCEPTION 'changed retention replay was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END
$replay_rewrite_check$;

RESET ROLE;

DO $stored_checks$
DECLARE
  manual_target_id uuid := (
    SELECT (target->>'target_id')::uuid FROM retention_manual_target
  );
  expired_target_id uuid := (
    SELECT (target->>'target_id')::uuid FROM retention_expired_target
  );
  relation_id uuid := (
    SELECT (result#>>'{relationship,relationship_id}')::uuid
    FROM retention_institution_relation
  );
BEGIN
  IF (SELECT (result->>'duplicate')::boolean FROM retention_renewal)
    OR NOT (SELECT (result->>'duplicate')::boolean
            FROM retention_renewal_replay)
    OR (SELECT (result->>'status') FROM retention_anonymized) <>
      'anonymized'
    OR NOT (SELECT (result->>'duplicate')::boolean
            FROM retention_anonymized_replay)
  THEN
    RAISE EXCEPTION 'retention mutation replay is unstable';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.promotion_targets
    WHERE promotion_target_id = manual_target_id
      AND status = 'anonymized'
      AND display_name = '已匿名化对象'
      AND phone IS NULL
      AND email IS NULL
      AND anonymization_reason = 'withdrawal'
      AND anonymized_at IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.promotion_targets
    WHERE promotion_target_id = expired_target_id
      AND status = 'anonymized'
      AND anonymization_reason = 'retention_expired'
  ) THEN
    RAISE EXCEPTION 'manual or due anonymization did not remove PII';
  END IF;

  IF EXISTS (
    SELECT 1 FROM app_data.promotion_target_assignments
    WHERE promotion_target_id = manual_target_id
      AND ended_at IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id = manual_target_id
      AND current_lifecycle_status = 'ended'
      AND current_follow_up_note IS NULL
  ) OR EXISTS (
    SELECT 1 FROM app_data.promotion_target_relationship_revisions
    WHERE promotion_target_id = manual_target_id
      AND (
        follow_up_note IS NOT NULL
        OR reason_detail IS NOT NULL
        OR requested_follow_up_note IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'assignment or project relationship PII remained';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.promotion_target_institution_relationships
    WHERE relationship_id = relation_id
      AND ended_at IS NOT NULL
      AND role_description = '[已匿名化]'
  ) THEN
    RAISE EXCEPTION 'institution relationship retained identifying context';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id = 'retention-contact-fact'
      AND lifecycle_status = 'active'
      AND reach_count = 3
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_target_links
    WHERE contact_id = 'retention-contact-fact'
      AND promotion_target_id = manual_target_id
      AND response_level = 2
  ) THEN
    RAISE EXCEPTION 'de-identified contact facts were not preserved';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.promotion_target_retention_events AS event_row
    WHERE event_row.promotion_target_id = manual_target_id
      AND to_jsonb(event_row)::text ~
        '待撤回对象|312 555|withdraw@example'
  ) THEN
    RAISE EXCEPTION 'retention audit contains target PII';
  END IF;
END
$stored_checks$;

ROLLBACK;
