\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0118_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0118.example.test', 'owner'
);

CREATE FUNCTION pg_temp.expect_0118_failure(
  expected_state text,
  expected_message text,
  statement_text text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE actual_state text; actual_message text;
BEGIN
  BEGIN
    EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state
    OR (expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0118 expected % / %, got % / %',
      expected_state, expected_message, actual_state, actual_message;
  END IF;
END
$function$;

INSERT INTO app_data.app_users(app_user_id,status)
VALUES ('00000000-0118-4000-8000-000000000002','active');
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '00000000-0118-4100-8000-000000000002',workspace_id,'0118 alternate project'
FROM fixture_0118_context;
INSERT INTO app_data.user_current_projects(app_user_id,project_id)
SELECT app_user_id,project_id FROM fixture_0118_context
ON CONFLICT (app_user_id) DO UPDATE SET project_id = EXCLUDED.project_id;

INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name,
  phone, email, status, created_by_app_user_id, created_at,
  anonymized_at, anonymization_reason
) SELECT target_id, context_row.workspace_id, 'person', label,
    NULL, NULL, 'active', context_row.app_user_id, transaction_timestamp(), NULL, NULL
FROM fixture_0118_context AS context_row
CROSS JOIN (VALUES
  ('00000000-0118-4200-8000-000000000001'::uuid,'0118 merged target A'),
  ('00000000-0118-4200-8000-000000000002'::uuid,'0118 merged target B'),
  ('00000000-0118-4200-8000-000000000003'::uuid,'0118 unmerged target')
) AS targets(target_id,label);

INSERT INTO app_data.promotion_target_assignments (
  assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id,assigned_at,ended_at,end_reason
) SELECT assignment_id,target_id,user_id,context_row.app_user_id,transaction_timestamp(),NULL,NULL
FROM fixture_0118_context AS context_row
CROSS JOIN (VALUES
  ('00000000-0118-4300-8000-000000000001'::uuid,'00000000-0118-4200-8000-000000000001'::uuid,NULL::uuid),
  ('00000000-0118-4300-8000-000000000002'::uuid,'00000000-0118-4200-8000-000000000002'::uuid,NULL::uuid),
  ('00000000-0118-4300-8000-000000000003'::uuid,'00000000-0118-4200-8000-000000000002'::uuid,
    '00000000-0118-4000-8000-000000000002'::uuid),
  ('00000000-0118-4300-8000-000000000004'::uuid,'00000000-0118-4200-8000-000000000003'::uuid,NULL::uuid)
) AS assignments(assignment_id,target_id,other_user_id)
CROSS JOIN LATERAL (SELECT coalesce(assignments.other_user_id,context_row.app_user_id) AS user_id) AS assign_to;

INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc
) SELECT '00000000-0118-4400-8000-000000000001',workspace_id,'person',app_user_id,transaction_timestamp()
FROM fixture_0118_context;
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id,workspace_id,target_type,promotion_target_id
) SELECT '00000000-0118-4400-8000-000000000001',workspace_id,'person',target_id
FROM fixture_0118_context CROSS JOIN (VALUES
  ('00000000-0118-4200-8000-000000000001'::uuid),
  ('00000000-0118-4200-8000-000000000002'::uuid)
) AS members(target_id);
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id,generation_id,workspace_id,target_type
) SELECT target_id,'00000000-0118-4400-8000-000000000001',workspace_id,'person'
FROM fixture_0118_context CROSS JOIN (VALUES
  ('00000000-0118-4200-8000-000000000001'::uuid),
  ('00000000-0118-4200-8000-000000000002'::uuid)
) AS members(target_id);

CREATE TEMP TABLE fixture_0118_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_private.personal_target_assignment_end_events_v1) AS event_count,
  (SELECT count(*) FROM app_data.promotion_target_retention_events) AS retention_count,
  (SELECT jsonb_agg(to_jsonb(event_row) ORDER BY event_row.event_id)
   FROM app_data.promotion_target_retention_events AS event_row) AS retention_events,
  (SELECT jsonb_agg(to_jsonb(target_row) ORDER BY promotion_target_id)
   FROM app_data.promotion_targets AS target_row
   WHERE promotion_target_id::text LIKE '00000000-0118-%') AS targets,
  (SELECT jsonb_agg(to_jsonb(assignment_row) ORDER BY assignment_id)
   FROM app_data.promotion_target_assignments AS assignment_row
   WHERE assignment_id::text LIKE '00000000-0118-%') AS assignments;

SELECT pg_temp.expect_0118_failure('42501','personal target assignment end is forbidden',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  context_row.app_user_id,context_row.workspace_id,context_row.project_id,
  '00000000-0118-4300-8000-000000000099'))
FROM fixture_0118_context AS context_row;
SELECT pg_temp.expect_0118_failure('42501','personal target assignment end is forbidden',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  '00000000-0118-4000-8000-000000000002',context_row.workspace_id,context_row.project_id,
  '00000000-0118-4300-8000-000000000002'))
FROM fixture_0118_context AS context_row;
SELECT pg_temp.expect_0118_failure('42501','personal target assignment end is forbidden',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  context_row.app_user_id,'00000000-0118-4500-8000-000000000001',context_row.project_id,
  '00000000-0118-4300-8000-000000000002'))
FROM fixture_0118_context AS context_row;
SELECT pg_temp.expect_0118_failure('42501','personal target assignment end is forbidden',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  context_row.app_user_id,context_row.workspace_id,'00000000-0118-4100-8000-000000000002',
  '00000000-0118-4300-8000-000000000002'))
FROM fixture_0118_context AS context_row;
SELECT pg_temp.expect_0118_failure('55000','personal target merge must be split before ending assignment',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  context_row.app_user_id,context_row.workspace_id,context_row.project_id,
  '00000000-0118-4300-8000-000000000001'))
FROM fixture_0118_context AS context_row;

DO $no_write_failures$
DECLARE before_row record;
BEGIN
  SELECT * INTO STRICT before_row FROM fixture_0118_before;
  IF before_row.event_count <> (SELECT count(*) FROM app_private.personal_target_assignment_end_events_v1)
    OR before_row.retention_count <> (SELECT count(*) FROM app_data.promotion_target_retention_events)
    OR before_row.targets IS DISTINCT FROM (
      SELECT jsonb_agg(to_jsonb(target_row) ORDER BY promotion_target_id)
      FROM app_data.promotion_targets AS target_row
      WHERE promotion_target_id::text LIKE '00000000-0118-%')
    OR before_row.assignments IS DISTINCT FROM (
      SELECT jsonb_agg(to_jsonb(assignment_row) ORDER BY assignment_id)
      FROM app_data.promotion_target_assignments AS assignment_row
      WHERE assignment_id::text LIKE '00000000-0118-%')
  THEN RAISE EXCEPTION '0118 rejected requests left writes'; END IF;
END
$no_write_failures$;

CREATE TEMP TABLE fixture_0118_first ON COMMIT DROP AS
SELECT app_data.end_personal_target_assignment_v1(
  context_row.app_user_id,context_row.workspace_id,context_row.project_id,
  '00000000-0118-4300-8000-000000000002') AS ended_at_utc
FROM fixture_0118_context AS context_row;
CREATE TEMP TABLE fixture_0118_replay ON COMMIT DROP AS
SELECT app_data.end_personal_target_assignment_v1(
  context_row.app_user_id,context_row.workspace_id,context_row.project_id,
  '00000000-0118-4300-8000-000000000002') AS ended_at_utc
FROM fixture_0118_context AS context_row;

UPDATE app_data.user_current_projects
SET project_id = '00000000-0118-4100-8000-000000000002'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0118_context);
SELECT pg_temp.expect_0118_failure('42501','personal target assignment end is forbidden',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  context_row.app_user_id,context_row.workspace_id,context_row.project_id,
  '00000000-0118-4300-8000-000000000002'))
FROM fixture_0118_context AS context_row;
SELECT pg_temp.expect_0118_failure('23505','personal target assignment end request was reused',format(
  'SELECT app_data.end_personal_target_assignment_v1(%L,%L,%L,%L)',
  context_row.app_user_id,context_row.workspace_id,'00000000-0118-4100-8000-000000000002',
  '00000000-0118-4300-8000-000000000002'))
FROM fixture_0118_context AS context_row;
UPDATE app_data.user_current_projects
SET project_id = (SELECT project_id FROM fixture_0118_context)
WHERE app_user_id = (SELECT app_user_id FROM fixture_0118_context);

DO $success_contract$
DECLARE first_time timestamptz; replay_time timestamptz; before_row record;
BEGIN
  SELECT ended_at_utc INTO STRICT first_time FROM fixture_0118_first;
  SELECT ended_at_utc INTO STRICT replay_time FROM fixture_0118_replay;
  SELECT * INTO STRICT before_row FROM fixture_0118_before;
  IF first_time IS DISTINCT FROM replay_time
    OR first_time IS NULL
    OR (SELECT ended_at FROM app_data.promotion_target_assignments
        WHERE assignment_id = '00000000-0118-4300-8000-000000000002') IS DISTINCT FROM first_time
    OR (SELECT end_reason FROM app_data.promotion_target_assignments
        WHERE assignment_id = '00000000-0118-4300-8000-000000000002') IS DISTINCT FROM 'user_requested'
    OR (SELECT count(*) FROM app_private.personal_target_assignment_end_events_v1
        WHERE assignment_id = '00000000-0118-4300-8000-000000000002') <> 1
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_assignment_end_events_v1
        WHERE assignment_id = '00000000-0118-4300-8000-000000000002'
          AND actor_app_user_id = (SELECT app_user_id FROM fixture_0118_context)
          AND workspace_id = (SELECT workspace_id FROM fixture_0118_context)
          AND project_id = (SELECT project_id FROM fixture_0118_context)
          AND reason = 'user_requested' AND ended_at_utc = first_time)
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_assignments
        WHERE assignment_id IN ('00000000-0118-4300-8000-000000000001',
          '00000000-0118-4300-8000-000000000003','00000000-0118-4300-8000-000000000004')
          AND ended_at IS NOT NULL)
    OR (SELECT count(*) FROM app_data.promotion_target_assignments
        WHERE promotion_target_id = '00000000-0118-4200-8000-000000000002'
          AND ended_at IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events) <> before_row.retention_count
    OR before_row.retention_events IS DISTINCT FROM (
      SELECT jsonb_agg(to_jsonb(event_row) ORDER BY event_row.event_id)
      FROM app_data.promotion_target_retention_events AS event_row)
    OR EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS assignment_row
      JOIN jsonb_array_elements(before_row.assignments) AS old_row
        ON old_row->>'assignment_id' = assignment_row.assignment_id::text
      WHERE assignment_row.assignment_id <> '00000000-0118-4300-8000-000000000002'
        AND to_jsonb(assignment_row) IS DISTINCT FROM old_row)
    OR (SELECT to_jsonb(target_row) FROM app_data.promotion_targets AS target_row
        WHERE promotion_target_id = '00000000-0118-4200-8000-000000000002') IS DISTINCT FROM
       (SELECT target_row FROM jsonb_array_elements(before_row.targets) AS target_row
        WHERE target_row->>'promotion_target_id' = '00000000-0118-4200-8000-000000000002')
  THEN RAISE EXCEPTION '0118 end/replay/target/retention contract drifted'; END IF;
END
$success_contract$;

SELECT pg_temp.expect_0118_failure('55000',NULL,$$
  UPDATE app_private.personal_target_assignment_end_events_v1
  SET reason = reason WHERE assignment_id = '00000000-0118-4300-8000-000000000002'
$$);
SELECT pg_temp.expect_0118_failure('55000',NULL,$$
  DELETE FROM app_private.personal_target_assignment_end_events_v1
  WHERE assignment_id = '00000000-0118-4300-8000-000000000002'
$$);

DO $no_privilege$
BEGIN
  IF has_table_privilege('public','app_private.personal_target_assignment_end_events_v1',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime','app_private.personal_target_assignment_end_events_v1',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_function_privilege('public',
      'app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',
      'app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION '0118 private event/function ACL drifted'; END IF;
END
$no_privilege$;

ROLLBACK;
