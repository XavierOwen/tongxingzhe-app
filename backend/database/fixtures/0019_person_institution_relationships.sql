\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE institution_relation_owner_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-institution-relations.example.test',
  'relationship-owner'
);

CREATE TEMP TABLE institution_relation_intruder_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-institution-relations.example.test',
  'relationship-intruder'
);

CREATE TEMP TABLE institution_relation_person AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  'person',
  '关系对象甲',
  NULL,
  NULL,
  'institution-relation-person'
);

CREATE TEMP TABLE institution_relation_second_person AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  'person',
  '关系对象乙',
  NULL,
  NULL,
  'institution-relation-second-person'
);

CREATE TEMP TABLE institution_relation_institution AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  'institution',
  '关系机构甲',
  NULL,
  NULL,
  'institution-relation-institution'
);

CREATE TEMP TABLE institution_relation_foreign_institution AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM institution_relation_intruder_context),
  (SELECT workspace_id FROM institution_relation_intruder_context),
  (SELECT project_id FROM institution_relation_intruder_context),
  'institution',
  '其他空间机构',
  NULL,
  NULL,
  'institution-relation-foreign-institution'
);

CREATE TEMP TABLE created_institution_relation AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  (SELECT (target->>'target_id')::uuid FROM institution_relation_person),
  (SELECT (target->>'target_id')::uuid
   FROM institution_relation_institution),
  'employment_representative',
  '项目协调员',
  'institution-relation-create-1'
);

CREATE TEMP TABLE replayed_institution_relation AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  (SELECT (target->>'target_id')::uuid FROM institution_relation_person),
  (SELECT (target->>'target_id')::uuid
   FROM institution_relation_institution),
  'employment_representative',
  '项目协调员',
  'institution-relation-create-1'
);

CREATE TEMP TABLE second_kind_institution_relation AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  (SELECT (target->>'target_id')::uuid FROM institution_relation_person),
  (SELECT (target->>'target_id')::uuid
   FROM institution_relation_institution),
  'partnership_service',
  '志愿顾问',
  'institution-relation-create-2'
);

DO $creation_rejections$
BEGIN
  BEGIN
    PERFORM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_person),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_institution),
      'employment_representative',
      '重复活动关系',
      'institution-relation-duplicate-active'
    );
    RAISE EXCEPTION 'duplicate active relation was accepted';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_person),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_second_person),
      'membership_affiliation',
      NULL,
      'institution-relation-same-type'
    );
    RAISE EXCEPTION 'same-type relation was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_person),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_foreign_institution),
      'membership_affiliation',
      NULL,
      'institution-relation-cross-workspace'
    );
    RAISE EXCEPTION 'cross-workspace relation was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_person),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_institution),
      'other',
      NULL,
      'institution-relation-other-without-role'
    );
    RAISE EXCEPTION 'other relation without role description was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_person),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_institution),
      'membership_affiliation',
      NULL,
      NULL
    );
    RAISE EXCEPTION 'null create mutation id was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_person),
      (SELECT (target->>'target_id')::uuid
       FROM institution_relation_institution),
      'ownership_governance',
      '改写重放',
      'institution-relation-create-1'
    );
    RAISE EXCEPTION 'changed relation replay was accepted';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
  END;
END
$creation_rejections$;

CREATE TEMP TABLE ended_institution_relation AS
SELECT result FROM app_data.end_target_institution_relationship(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  (SELECT (result#>>'{relationship,relationship_id}')::uuid
   FROM created_institution_relation),
  1,
  'institution-relation-end-1'
);

CREATE TEMP TABLE replayed_institution_relation_end AS
SELECT result FROM app_data.end_target_institution_relationship(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  (SELECT (result#>>'{relationship,relationship_id}')::uuid
   FROM created_institution_relation),
  1,
  'institution-relation-end-1'
);

DO $end_rejections$
BEGIN
  BEGIN
    PERFORM app_data.end_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (result#>>'{relationship,relationship_id}')::uuid
       FROM created_institution_relation),
      1,
      NULL
    );
    RAISE EXCEPTION 'null end mutation id was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;
END
$end_rejections$;

CREATE TEMP TABLE recreated_institution_relation AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context),
  (SELECT (target->>'target_id')::uuid FROM institution_relation_person),
  (SELECT (target->>'target_id')::uuid
   FROM institution_relation_institution),
  'employment_representative',
  '重新任职',
  'institution-relation-create-3'
);

CREATE TEMP TABLE assigned_institution_relations AS
SELECT relationship
FROM app_data.list_assigned_target_institution_relationships(
  (SELECT app_user_id FROM institution_relation_owner_context),
  (SELECT workspace_id FROM institution_relation_owner_context),
  (SELECT project_id FROM institution_relation_owner_context)
);

RESET ROLE;

DO $relationship_checks$
DECLARE
  first_relationship_id uuid := (
    SELECT (result#>>'{relationship,relationship_id}')::uuid
    FROM created_institution_relation
  );
BEGIN
  IF (SELECT (result->>'duplicate')::boolean
      FROM created_institution_relation)
    OR NOT (SELECT (result->>'duplicate')::boolean
            FROM replayed_institution_relation)
    OR (SELECT (result#>>'{relationship,status}')
        FROM ended_institution_relation) <> 'ended'
    OR NOT (SELECT (result->>'duplicate')::boolean
            FROM replayed_institution_relation_end)
    OR (SELECT count(*) FROM assigned_institution_relations) <> 3
  THEN
    RAISE EXCEPTION 'institution relation replay or history is unstable';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.promotion_target_institution_relationships
    WHERE relationship_id = first_relationship_id
      AND ended_at IS NOT NULL
      AND current_revision = 2
  ) OR (
    SELECT count(*)
    FROM app_data.promotion_target_institution_relation_revisions
    WHERE relationship_id = first_relationship_id
  ) <> 2 THEN
    RAISE EXCEPTION 'institution relation end history diverged';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.list_personal_project_contexts(
      'https://synthetic-institution-relations.example.test',
      'relationship-owner'
    )
    WHERE is_current
      AND capabilities @> ARRAY[
        'view_assigned_target_pii',
        'manage_assigned_target_relations'
      ]::text[]
  ) THEN
    RAISE EXCEPTION 'institution relation capability is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.promotion_target_assignments
    WHERE promotion_target_id IN (
      SELECT (target->>'target_id')::uuid
      FROM institution_relation_person
      UNION ALL
      SELECT (target->>'target_id')::uuid
      FROM institution_relation_institution
    )
      AND app_user_id = (
        SELECT app_user_id FROM institution_relation_intruder_context
      )
  ) OR EXISTS (
    SELECT 1
    FROM app_data.contact_target_links
    WHERE promotion_target_id IN (
      SELECT (target->>'target_id')::uuid
      FROM institution_relation_person
      UNION ALL
      SELECT (target->>'target_id')::uuid
      FROM institution_relation_institution
    )
  ) THEN
    RAISE EXCEPTION 'institution relation granted access or linked a contact';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.warehouse_outbox
    WHERE analytics_payload::text ~*
      '(关系对象甲|关系机构甲|项目协调员|志愿顾问|重新任职)'
  ) THEN
    RAISE EXCEPTION 'institution relation PII entered warehouse payload';
  END IF;

  BEGIN
    UPDATE app_data.promotion_target_institution_relation_revisions
    SET changed_at = clock_timestamp()
    WHERE relationship_id = first_relationship_id;
    RAISE EXCEPTION 'institution relation history was mutable';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      NULL;
  END;
END
$relationship_checks$;

UPDATE app_data.promotion_target_assignments
SET ended_at = clock_timestamp(),
    end_reason = 'synthetic access revocation'
WHERE promotion_target_id = (
  SELECT (target->>'target_id')::uuid
  FROM institution_relation_institution
)
  AND app_user_id = (
    SELECT app_user_id FROM institution_relation_owner_context
  )
  AND ended_at IS NULL;

SET LOCAL ROLE tongxingzhe_runtime;

DO $revoked_access_check$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM app_data.list_assigned_target_institution_relationships(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context)
    )
  ) THEN
    RAISE EXCEPTION 'revoked endpoint relationship remained visible';
  END IF;

  BEGIN
    PERFORM app_data.end_target_institution_relationship(
      (SELECT app_user_id FROM institution_relation_owner_context),
      (SELECT workspace_id FROM institution_relation_owner_context),
      (SELECT project_id FROM institution_relation_owner_context),
      (SELECT (result#>>'{relationship,relationship_id}')::uuid
       FROM recreated_institution_relation),
      1,
      'institution-relation-after-revocation'
    );
    RAISE EXCEPTION 'revoked assignee ended institution relation';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$revoked_access_check$;

RESET ROLE;

ROLLBACK;
