\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0115_owner AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0115-relationship.example.test', 'owner'
);
GRANT SELECT ON fixture_0115_owner TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0115_person_a AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0115_owner),
  (SELECT workspace_id FROM fixture_0115_owner),
  (SELECT project_id FROM fixture_0115_owner),
  'person', '0115 person A', NULL, NULL, '0115-person-a'
);
CREATE TEMP TABLE fixture_0115_person_b AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0115_owner),
  (SELECT workspace_id FROM fixture_0115_owner),
  (SELECT project_id FROM fixture_0115_owner),
  'person', '0115 person B', NULL, NULL, '0115-person-b'
);
CREATE TEMP TABLE fixture_0115_institution_a AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0115_owner),
  (SELECT workspace_id FROM fixture_0115_owner),
  (SELECT project_id FROM fixture_0115_owner),
  'institution', '0115 institution A', NULL, NULL, '0115-institution-a'
);
CREATE TEMP TABLE fixture_0115_institution_b AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0115_owner),
  (SELECT workspace_id FROM fixture_0115_owner),
  (SELECT project_id FROM fixture_0115_owner),
  'institution', '0115 institution B', NULL, NULL, '0115-institution-b'
);
CREATE TEMP TABLE fixture_0115_institution_c AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0115_owner),
  (SELECT workspace_id FROM fixture_0115_owner),
  (SELECT project_id FROM fixture_0115_owner),
  'institution', '0115 institution C', NULL, NULL, '0115-institution-c'
);
CREATE TEMP TABLE fixture_0115_malformed_institution AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0115_owner),
  (SELECT workspace_id FROM fixture_0115_owner),
  (SELECT project_id FROM fixture_0115_owner),
  'institution', '0115 malformed-map institution', NULL, NULL,
  '0115-malformed-map-institution'
);
GRANT SELECT ON fixture_0115_person_a, fixture_0115_person_b,
  fixture_0115_institution_a, fixture_0115_institution_b,
  fixture_0115_institution_c, fixture_0115_malformed_institution
  TO tongxingzhe_runtime;
RESET ROLE;

CREATE TEMP TABLE fixture_0115_ids AS
SELECT
  (SELECT app_user_id FROM fixture_0115_owner) AS app_user_id,
  (SELECT workspace_id FROM fixture_0115_owner) AS workspace_id,
  (SELECT project_id FROM fixture_0115_owner) AS project_id,
  (SELECT (target->>'target_id')::uuid FROM fixture_0115_person_a) AS person_a,
  (SELECT (target->>'target_id')::uuid FROM fixture_0115_person_b) AS person_b,
  (SELECT (target->>'target_id')::uuid FROM fixture_0115_institution_a) AS institution_a,
  (SELECT (target->>'target_id')::uuid FROM fixture_0115_institution_b) AS institution_b,
  (SELECT (target->>'target_id')::uuid FROM fixture_0115_institution_c) AS institution_c,
  (SELECT (target->>'target_id')::uuid FROM fixture_0115_malformed_institution)
    AS malformed_institution,
  '00000000-0115-4000-8000-000000000001'::uuid AS person_generation,
  '00000000-0115-4000-8000-000000000002'::uuid AS institution_generation;
GRANT SELECT ON fixture_0115_ids TO tongxingzhe_runtime;

-- A valid relationship created before activation remains unbound.
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0115_unbound_create AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0115_ids),
  (SELECT workspace_id FROM fixture_0115_ids),
  (SELECT project_id FROM fixture_0115_ids),
  (SELECT person_a FROM fixture_0115_ids),
  (SELECT institution_c FROM fixture_0115_ids),
  'membership_affiliation', 'unbound history', '0115-unbound-create'
);
RESET ROLE;

INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id, workspace_id, target_type, created_by_app_user_id,
  activated_at_utc
)
SELECT person_generation, workspace_id, 'person', app_user_id, clock_timestamp()
FROM fixture_0115_ids
UNION ALL
SELECT institution_generation, workspace_id, 'institution', app_user_id,
  clock_timestamp()
FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id, workspace_id, target_type, promotion_target_id
)
SELECT person_generation, workspace_id, 'person', person_a FROM fixture_0115_ids
UNION ALL
SELECT person_generation, workspace_id, 'person', person_b FROM fixture_0115_ids
UNION ALL
SELECT institution_generation, workspace_id, 'institution', institution_a
FROM fixture_0115_ids
UNION ALL
SELECT institution_generation, workspace_id, 'institution', institution_b
FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT person_a, person_generation, workspace_id, 'person' FROM fixture_0115_ids
UNION ALL
SELECT person_b, person_generation, workspace_id, 'person' FROM fixture_0115_ids
UNION ALL
SELECT institution_a, institution_generation, workspace_id, 'institution'
FROM fixture_0115_ids
UNION ALL
SELECT institution_b, institution_generation, workspace_id, 'institution'
FROM fixture_0115_ids;
-- This endpoint map is incomplete: the institution generation has two members
-- but only one active member.
INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id, workspace_id, target_type, created_by_app_user_id,
  activated_at_utc
)
SELECT '00000000-0115-4000-8000-000000000003'::uuid,
  workspace_id, 'institution', app_user_id, clock_timestamp()
FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id, workspace_id, target_type, promotion_target_id
)
SELECT '00000000-0115-4000-8000-000000000003'::uuid,
  workspace_id, 'institution', malformed_institution FROM fixture_0115_ids
UNION ALL
SELECT '00000000-0115-4000-8000-000000000003'::uuid,
  workspace_id, 'institution', institution_c FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT malformed_institution, '00000000-0115-4000-8000-000000000003'::uuid,
  workspace_id, 'institution' FROM fixture_0115_ids;

SET LOCAL ROLE tongxingzhe_runtime;
DO $incomplete_endpoint_map$
DECLARE
  person_id uuid := (SELECT person_a FROM fixture_0115_ids);
  institution_id uuid := (SELECT malformed_institution FROM fixture_0115_ids);
BEGIN
  BEGIN
    PERFORM result FROM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM fixture_0115_ids),
      (SELECT workspace_id FROM fixture_0115_ids),
      (SELECT project_id FROM fixture_0115_ids), person_id, institution_id,
      'membership_affiliation', 'incomplete institution map',
      '0115-incomplete-dual-map'
    );
    RAISE EXCEPTION 'relationship creation accepted an incomplete endpoint map';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    IF SQLERRM <> 'personal target merge generation is incomplete' THEN
      RAISE;
    END IF;
  END;
END
$incomplete_endpoint_map$;
RESET ROLE;
DO $incomplete_endpoint_map_no_partial$
DECLARE
  person_id uuid := (SELECT person_a FROM fixture_0115_ids);
  institution_id uuid := (SELECT malformed_institution FROM fixture_0115_ids);
BEGIN
  IF EXISTS (
    SELECT 1 FROM app_data.promotion_target_institution_relationships
    WHERE person_target_id = person_id
      AND institution_target_id = institution_id
  ) OR EXISTS (
    SELECT 1 FROM app_data.promotion_target_institution_relation_revisions
    WHERE mutation_id = '0115-incomplete-dual-map'
  ) THEN
    RAISE EXCEPTION 'incomplete endpoint map left a relationship or revision row';
  END IF;
END
$incomplete_endpoint_map_no_partial$;

-- Switch the same synthetic endpoint to a complete map in another workspace;
-- this isolates the resolver's workspace-consistency rejection from the
-- incomplete-member rejection above.
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE promotion_target_id = (SELECT malformed_institution FROM fixture_0115_ids);
INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id, workspace_id, target_type, created_by_app_user_id,
  activated_at_utc
)
SELECT '00000000-0115-4000-8000-000000000004'::uuid,
  '00000000-0115-4000-8000-000000000005'::uuid,
  'institution', app_user_id, clock_timestamp()
FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id, workspace_id, target_type, promotion_target_id
)
SELECT '00000000-0115-4000-8000-000000000004'::uuid,
  '00000000-0115-4000-8000-000000000005'::uuid,
  'institution', malformed_institution FROM fixture_0115_ids
UNION ALL
SELECT '00000000-0115-4000-8000-000000000004'::uuid,
  '00000000-0115-4000-8000-000000000005'::uuid,
  'institution', institution_c FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT malformed_institution, '00000000-0115-4000-8000-000000000004'::uuid,
  '00000000-0115-4000-8000-000000000005'::uuid, 'institution'
FROM fixture_0115_ids;
INSERT INTO app_data.promotion_target_project_relationships (
  promotion_target_id, project_id, current_stage, current_follow_up_note,
  established_by_app_user_id
)
SELECT person_a, project_id, 2, 'active merge note', app_user_id
FROM fixture_0115_ids;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0115_unbound_end AS
SELECT result FROM app_data.end_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0115_ids),
  (SELECT workspace_id FROM fixture_0115_ids),
  (SELECT project_id FROM fixture_0115_ids),
  (SELECT (result->'relationship'->>'relationship_id')::uuid
   FROM fixture_0115_unbound_create),
  1, '0115-unbound-end-after-activation'
);
CREATE TEMP TABLE fixture_0115_bound_create AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0115_ids),
  (SELECT workspace_id FROM fixture_0115_ids),
  (SELECT project_id FROM fixture_0115_ids),
  (SELECT person_a FROM fixture_0115_ids),
  (SELECT institution_a FROM fixture_0115_ids),
  'employment_representative', 'two independent generations',
  '0115-bound-create'
);
CREATE TEMP TABLE fixture_0115_single_side_create AS
SELECT result FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0115_ids),
  (SELECT workspace_id FROM fixture_0115_ids),
  (SELECT project_id FROM fixture_0115_ids),
  (SELECT person_b FROM fixture_0115_ids),
  (SELECT institution_c FROM fixture_0115_ids),
  'partnership_service', 'person side only', '0115-single-side-create'
);
DO $forged_revision_generation$
DECLARE
  target_relationship_id uuid := (
    SELECT (result->'relationship'->>'relationship_id')::uuid
    FROM fixture_0115_bound_create
  );
BEGIN
  BEGIN
    UPDATE app_data.promotion_target_institution_relation_revisions
    SET person_merge_generation_id =
      '00000000-0115-4000-8000-000000000099'::uuid
    WHERE relationship_id = target_relationship_id
      AND revision_number = 1;
    RAISE EXCEPTION 'caller changed a revision generation binding';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO app_data.promotion_target_institution_relation_revisions (
      relationship_id, revision_number, event_type, old_status, new_status,
      changed_by_app_user_id, mutation_id, requested_base_revision,
      person_merge_generation_id
    ) VALUES (
      target_relationship_id, 99, 'ended', 'active',
      'ended', (SELECT app_user_id FROM fixture_0115_ids),
      '0115-forged-revision-generation', 1,
      '00000000-0115-4000-8000-000000000099'::uuid
    );
    RAISE EXCEPTION 'caller supplied a revision generation binding';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

END
$forged_revision_generation$;
DO $workspace_mismatched_endpoint_map$
DECLARE
  person_id uuid := (SELECT person_a FROM fixture_0115_ids);
  institution_id uuid := (SELECT malformed_institution FROM fixture_0115_ids);
BEGIN
  BEGIN
    PERFORM result FROM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM fixture_0115_ids),
      (SELECT workspace_id FROM fixture_0115_ids),
      (SELECT project_id FROM fixture_0115_ids), person_id, institution_id,
      'membership_affiliation', 'workspace-mismatched institution map',
      '0115-workspace-mismatched-dual-map'
    );
    RAISE EXCEPTION 'relationship creation accepted a workspace-mismatched endpoint map';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    IF SQLERRM <> 'personal target merge generation is inconsistent' THEN
      RAISE;
    END IF;
  END;

END
$workspace_mismatched_endpoint_map$;
RESET ROLE;

-- The institution endpoint is deliberately labelled as a person in a
-- complete, same-workspace generation. The relationship writer must resolve
-- its actual target type rather than accept the misleading private map.
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE promotion_target_id = (SELECT malformed_institution FROM fixture_0115_ids);
INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id, workspace_id, target_type, created_by_app_user_id,
  activated_at_utc
)
SELECT '00000000-0115-4000-8000-000000000006'::uuid,
  workspace_id, 'person', app_user_id, clock_timestamp()
FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id, workspace_id, target_type, promotion_target_id
)
SELECT '00000000-0115-4000-8000-000000000006'::uuid,
  workspace_id, 'person', malformed_institution FROM fixture_0115_ids
UNION ALL
SELECT '00000000-0115-4000-8000-000000000006'::uuid,
  workspace_id, 'person', institution_c FROM fixture_0115_ids;
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT malformed_institution, '00000000-0115-4000-8000-000000000006'::uuid,
  workspace_id, 'person' FROM fixture_0115_ids;

SET LOCAL ROLE tongxingzhe_runtime;
DO $type_mismatched_endpoint_map$
DECLARE
  person_id uuid := (SELECT person_a FROM fixture_0115_ids);
  institution_id uuid := (SELECT malformed_institution FROM fixture_0115_ids);
BEGIN
  BEGIN
    PERFORM result FROM app_data.create_target_institution_relationship(
      (SELECT app_user_id FROM fixture_0115_ids),
      (SELECT workspace_id FROM fixture_0115_ids),
      (SELECT project_id FROM fixture_0115_ids), person_id, institution_id,
      'membership_affiliation', 'type-mismatched institution map',
      '0115-target-type-mismatched-dual-map'
    );
    RAISE EXCEPTION 'relationship creation accepted a target-type-mismatched endpoint map';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    IF SQLERRM <> 'personal target merge generation is inconsistent' THEN
      RAISE;
    END IF;
  END;
END
$type_mismatched_endpoint_map$;
RESET ROLE;

DO $forged_revision_no_partial_history$
DECLARE
  target_relationship_id uuid := (
    SELECT (result->'relationship'->>'relationship_id')::uuid
    FROM fixture_0115_bound_create
  );
BEGIN
  IF (SELECT count(*)
      FROM app_data.promotion_target_institution_relation_revisions
      WHERE relationship_id = target_relationship_id) <> 1
    OR EXISTS (
      SELECT 1 FROM app_data.promotion_target_institution_relation_revisions
      WHERE mutation_id = '0115-forged-revision-generation'
    ) OR EXISTS (
      SELECT 1 FROM app_data.promotion_target_institution_relation_revisions
      WHERE mutation_id IN (
        '0115-incomplete-dual-map',
        '0115-workspace-mismatched-dual-map',
        '0115-target-type-mismatched-dual-map'
      )
    ) OR EXISTS (
      SELECT 1 FROM app_data.promotion_target_institution_relationships
      WHERE person_target_id = (SELECT person_a FROM fixture_0115_ids)
        AND institution_target_id =
          (SELECT malformed_institution FROM fixture_0115_ids)
    ) THEN
    RAISE EXCEPTION 'forged revision or malformed endpoint map attempt left partial history';
  END IF;
END
$forged_revision_no_partial_history$;

DO $functional$
DECLARE
  unbound_relationship_id uuid;
  bound_relationship_id uuid;
  single_side_relationship_id uuid;
  forged_generation uuid := '00000000-0115-4000-8000-000000000099';
BEGIN
  SELECT (result->'relationship'->>'relationship_id')::uuid
  INTO STRICT unbound_relationship_id FROM fixture_0115_unbound_create;
  SELECT (result->'relationship'->>'relationship_id')::uuid
  INTO STRICT bound_relationship_id FROM fixture_0115_bound_create;
  SELECT (result->'relationship'->>'relationship_id')::uuid
  INTO STRICT single_side_relationship_id FROM fixture_0115_single_side_create;

  IF (SELECT person_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = unbound_relationship_id) IS NOT NULL
    OR (SELECT institution_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = unbound_relationship_id) IS NOT NULL
    OR (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions
      WHERE relationship_id = unbound_relationship_id
        AND event_type = 'created'
        AND person_merge_generation_id IS NULL
        AND institution_merge_generation_id IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions
      WHERE relationship_id = unbound_relationship_id
        AND event_type = 'ended'
        AND person_merge_generation_id = (SELECT person_generation FROM fixture_0115_ids)
        AND institution_merge_generation_id IS NULL) <> 1
  THEN
    RAISE EXCEPTION 'no-generation history was unexpectedly bound';
  END IF;

  IF (SELECT person_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = bound_relationship_id) <>
        (SELECT person_generation FROM fixture_0115_ids)
    OR (SELECT institution_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = bound_relationship_id) <>
        (SELECT institution_generation FROM fixture_0115_ids)
    OR (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions
      WHERE relationship_id = bound_relationship_id
        AND event_type = 'created'
        AND person_merge_generation_id = (SELECT person_generation FROM fixture_0115_ids)
        AND institution_merge_generation_id = (SELECT institution_generation FROM fixture_0115_ids)) <> 1
    OR (SELECT person_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = single_side_relationship_id) <>
        (SELECT person_generation FROM fixture_0115_ids)
    OR (SELECT institution_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = single_side_relationship_id) IS NOT NULL
  THEN
    RAISE EXCEPTION 'independent endpoint generation binding failed';
  END IF;

  BEGIN
    UPDATE app_data.promotion_target_institution_relationships
    SET person_merge_generation_id = forged_generation,
        ended_at = clock_timestamp(),
        current_revision = current_revision + 1,
        updated_by_app_user_id = (SELECT app_user_id FROM fixture_0115_ids),
        updated_at = clock_timestamp()
    WHERE relationship_id = bound_relationship_id;
    RAISE EXCEPTION 'caller changed a relationship generation binding';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO app_data.promotion_target_institution_relationships (
      workspace_id, person_target_id, institution_target_id,
      relationship_kind, role_description, created_by_app_user_id,
      updated_by_app_user_id, person_merge_generation_id
    ) SELECT workspace_id, person_a, malformed_institution,
      'membership_affiliation', 'wrong generation member',
      app_user_id, app_user_id, institution_generation
    FROM fixture_0115_ids;
    RAISE EXCEPTION 'caller supplied a wrong relationship generation member';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM app_data.promotion_target_institution_relationships
    WHERE person_target_id = (SELECT person_a FROM fixture_0115_ids)
      AND institution_target_id =
        (SELECT malformed_institution FROM fixture_0115_ids)
  ) OR EXISTS (
    SELECT 1 FROM app_data.promotion_target_institution_relation_revisions
      AS revision_row
    JOIN app_data.promotion_target_institution_relationships AS relation_row
      USING (relationship_id)
    WHERE relation_row.person_target_id = (SELECT person_a FROM fixture_0115_ids)
      AND relation_row.institution_target_id =
        (SELECT malformed_institution FROM fixture_0115_ids)
  ) THEN
    RAISE EXCEPTION 'wrong generation member attempt left relationship or revision state';
  END IF;

  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      (SELECT app_user_id FROM fixture_0115_ids),
      (SELECT workspace_id FROM fixture_0115_ids),
      (SELECT project_id FROM fixture_0115_ids),
      (SELECT person_a FROM fixture_0115_ids), 'anonymize', 'withdrawal',
      '0115-active-member-anonymize'
    );
    RAISE EXCEPTION 'active merge member anonymization succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  IF (SELECT status FROM app_data.promotion_targets
      WHERE promotion_target_id = (SELECT person_a FROM fixture_0115_ids)) <> 'active'
    OR NOT EXISTS (
      SELECT 1 FROM app_data.promotion_target_assignments
      WHERE promotion_target_id = (SELECT person_a FROM fixture_0115_ids)
        AND ended_at IS NULL
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id = (SELECT person_a FROM fixture_0115_ids)
        AND current_follow_up_note = 'active merge note'
    )
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events
      WHERE mutation_id = '0115-active-member-anonymize') <> 0
  THEN
    RAISE EXCEPTION 'rejected anonymization left partial changes';
  END IF;
END
$functional$;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0115_anonymize_nonmember AS
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM fixture_0115_ids),
  (SELECT workspace_id FROM fixture_0115_ids),
  (SELECT project_id FROM fixture_0115_ids),
  (SELECT institution_c FROM fixture_0115_ids), 'anonymize', 'withdrawal',
  '0115-anonymize-nonmember-endpoint'
);
CREATE TEMP TABLE fixture_0115_end AS
SELECT result FROM app_data.end_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0115_ids),
  (SELECT workspace_id FROM fixture_0115_ids),
  (SELECT project_id FROM fixture_0115_ids),
  (SELECT (result->'relationship'->>'relationship_id')::uuid
   FROM fixture_0115_bound_create),
  1, '0115-bound-end'
);
RESET ROLE;

DO $end_binding$
DECLARE
  requested_relationship_id uuid := (
    SELECT (result->'relationship'->>'relationship_id')::uuid
    FROM fixture_0115_end
  );
BEGIN
  IF (SELECT person_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = requested_relationship_id) IS DISTINCT FROM
        (SELECT person_generation FROM fixture_0115_ids)
    OR (SELECT institution_merge_generation_id
      FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = requested_relationship_id) IS DISTINCT FROM
        (SELECT institution_generation FROM fixture_0115_ids)
    OR (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions
      WHERE promotion_target_institution_relation_revisions.relationship_id = requested_relationship_id
        AND event_type = 'ended'
        AND person_merge_generation_id = (SELECT person_generation FROM fixture_0115_ids)
        AND institution_merge_generation_id = (SELECT institution_generation FROM fixture_0115_ids)) <> 1
  THEN
    RAISE EXCEPTION 'end revision lost create or end-time endpoint bindings';
  END IF;
END
$end_binding$;

DO $nonmember_anonymization$
DECLARE
  requested_relationship_id uuid := (
    SELECT (result->'relationship'->>'relationship_id')::uuid
    FROM fixture_0115_single_side_create
  );
BEGIN
  IF (SELECT status FROM app_data.promotion_targets
      WHERE promotion_target_id = (SELECT institution_c FROM fixture_0115_ids)) <> 'anonymized'
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events
      WHERE mutation_id = '0115-anonymize-nonmember-endpoint') <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions
      WHERE relationship_id = requested_relationship_id
        AND event_type = 'ended'
        AND person_merge_generation_id = (SELECT person_generation FROM fixture_0115_ids)
        AND institution_merge_generation_id IS NULL) <> 1
  THEN
    RAISE EXCEPTION 'non-member endpoint anonymization did not bind the remaining active side';
  END IF;
END
$nonmember_anonymization$;

-- The generic 0114 binder also rechecks lifecycle state after its fence wait.
-- This privileged fixture insert exercises the trigger directly, independent
-- of runtime table-write grants or API authorization.
DO $generic_binder_post_anonymization$
DECLARE
  requested_target_id uuid := (SELECT institution_c FROM fixture_0115_ids);
  requested_project_id uuid := (SELECT project_id FROM fixture_0115_ids);
  requested_app_user_id uuid := (SELECT app_user_id FROM fixture_0115_ids);
BEGIN
  BEGIN
    INSERT INTO app_data.promotion_target_project_relationships (
      promotion_target_id, project_id, current_stage,
      established_by_app_user_id
    ) VALUES (
      requested_target_id, requested_project_id, 1, requested_app_user_id
    );
    RAISE EXCEPTION 'generic target fact binder accepted an anonymized target';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'personal target fact requires an active target' THEN
      RAISE;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id = requested_target_id
      AND project_id = requested_project_id
  ) OR EXISTS (
    SELECT 1 FROM app_data.promotion_target_relationship_revisions
    WHERE promotion_target_id = requested_target_id
      AND project_id = requested_project_id
  ) THEN
    RAISE EXCEPTION 'generic target fact binder left project history after rejection';
  END IF;
END
$generic_binder_post_anonymization$;

ROLLBACK;
