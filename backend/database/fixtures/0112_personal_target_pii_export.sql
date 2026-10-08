\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0112_owner_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0112.example.test', 'owner'
);
CREATE TEMP TABLE fixture_0112_other_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0112.example.test', 'other-owner'
);
CREATE TEMP TABLE fixture_0112_inactive_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0112.example.test', 'inactive-owner'
);
CREATE TEMP TABLE fixture_0112_deleted_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0112.example.test', 'deleted-owner'
);
CREATE TEMP TABLE fixture_0112_exports (
  case_name text PRIMARY KEY,
  export_bytes bytea NOT NULL
) ON COMMIT DROP;

INSERT INTO app_data.user_current_projects (app_user_id, project_id)
SELECT app_user_id, project_id FROM fixture_0112_owner_context
UNION ALL
SELECT app_user_id, project_id FROM fixture_0112_other_context
UNION ALL
SELECT app_user_id, project_id FROM fixture_0112_inactive_context
UNION ALL
SELECT app_user_id, project_id FROM fixture_0112_deleted_context
ON CONFLICT (app_user_id) DO UPDATE SET project_id = EXCLUDED.project_id;

CREATE FUNCTION pg_temp.expect_failure(
  expected_state text,
  statement_text text,
  forbidden_fragment text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  actual_state text;
  actual_message text;
BEGIN
  BEGIN
    EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      actual_state = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION 'expected SQLSTATE %, got %', expected_state, actual_state;
  END IF;
  IF forbidden_fragment IS NOT NULL
    AND position(forbidden_fragment IN COALESCE(actual_message, '')) > 0
  THEN
    RAISE EXCEPTION 'expected error to omit private input';
  END IF;
END
$function$;

GRANT ALL ON
  fixture_0112_owner_context,
  fixture_0112_other_context,
  fixture_0112_inactive_context,
  fixture_0112_deleted_context,
  fixture_0112_exports
TO tongxingzhe_runtime;

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '00000000-0112-4000-8000-000000000099'::uuid,
  (SELECT workspace_id FROM fixture_0112_owner_context),
  'Non-current export project',
  'active',
  false
);

INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name,
  phone, email, status, created_by_app_user_id, created_at,
  anonymized_at, anonymization_reason
) VALUES
  (
    '00000000-0112-4000-8000-000000000001'::uuid,
    (SELECT workspace_id FROM fixture_0112_owner_context),
    'person', E'张三 "A" \\ 路\n下一行\t😀', '+1 312 555 0112', NULL,
    'active', (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-02 03:04:05+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000002'::uuid,
    (SELECT workspace_id FROM fixture_0112_owner_context),
    'institution', '  原值保留  ', NULL, 'Case@Example.TEST ',
    'active', (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-02 03:04:05+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000003'::uuid,
    (SELECT workspace_id FROM fixture_0112_owner_context),
    'person', 'ENDED_ASSIGNMENT_SENTINEL', '+1 312 555 0113', NULL,
    'active', (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000004'::uuid,
    (SELECT workspace_id FROM fixture_0112_owner_context),
    'person', 'OTHER_ASSIGNEE_SENTINEL', '+1 312 555 0114', NULL,
    'active', (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000005'::uuid,
    (SELECT workspace_id FROM fixture_0112_owner_context),
    'person', '已匿名化对象', NULL, NULL,
    'anonymized', (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', '2026-02-01 00:00:00+00', 'withdrawal'
  ),
  (
    '00000000-0112-4000-8000-000000000006'::uuid,
    (SELECT workspace_id FROM fixture_0112_other_context),
    'person', 'OTHER_WORKSPACE_SENTINEL', '+1 312 555 0116', NULL,
    'active', (SELECT app_user_id FROM fixture_0112_other_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000007'::uuid,
    (SELECT workspace_id FROM fixture_0112_owner_context),
    'person', 'SORT_EARLIER_SENTINEL', NULL, NULL,
    'active', (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 12:00:00+00', NULL, NULL
  );

INSERT INTO app_data.promotion_target_assignments (
  assignment_id, promotion_target_id, app_user_id,
  assigned_by_app_user_id, assigned_at, ended_at, end_reason
) VALUES
  (
    '00000000-0112-4000-8000-000000000011'::uuid,
    '00000000-0112-4000-8000-000000000001'::uuid,
    (SELECT app_user_id FROM fixture_0112_owner_context),
    (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000012'::uuid,
    '00000000-0112-4000-8000-000000000002'::uuid,
    (SELECT app_user_id FROM fixture_0112_owner_context),
    (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000013'::uuid,
    '00000000-0112-4000-8000-000000000003'::uuid,
    (SELECT app_user_id FROM fixture_0112_owner_context),
    (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', '2026-02-01 00:00:00+00', 'unassigned'
  ),
  (
    '00000000-0112-4000-8000-000000000014'::uuid,
    '00000000-0112-4000-8000-000000000004'::uuid,
    (SELECT app_user_id FROM fixture_0112_other_context),
    (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000015'::uuid,
    '00000000-0112-4000-8000-000000000005'::uuid,
    (SELECT app_user_id FROM fixture_0112_owner_context),
    (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', '2026-02-01 00:00:00+00', 'target_anonymized'
  ),
  (
    '00000000-0112-4000-8000-000000000016'::uuid,
    '00000000-0112-4000-8000-000000000006'::uuid,
    (SELECT app_user_id FROM fixture_0112_owner_context),
    (SELECT app_user_id FROM fixture_0112_other_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  ),
  (
    '00000000-0112-4000-8000-000000000017'::uuid,
    '00000000-0112-4000-8000-000000000007'::uuid,
    (SELECT app_user_id FROM fixture_0112_owner_context),
    (SELECT app_user_id FROM fixture_0112_owner_context),
    '2026-01-01 00:00:00+00', NULL, NULL
  );

DO $capabilities$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.list_personal_project_contexts(
      'https://synthetic-0112.example.test', 'owner'
    ) AS context_row
    WHERE context_row.is_current
      AND 'export_target_pii' = ANY(context_row.capabilities)
      AND 'view_assigned_target_pii' = ANY(context_row.capabilities)
  ) THEN
    RAISE EXCEPTION 'personal context did not derive both export capabilities';
  END IF;
END
$capabilities$;

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0112_exports
SELECT 'canonical', app_data.prepare_personal_target_pii_export_v1(
  'https://synthetic-0112.example.test', 'owner',
  (SELECT project_id FROM fixture_0112_owner_context),
  transaction_timestamp() - interval '1 minute'
);
INSERT INTO fixture_0112_exports
SELECT 'empty', app_data.prepare_personal_target_pii_export_v1(
  'https://synthetic-0112.example.test', 'other-owner',
  (SELECT project_id FROM fixture_0112_other_context),
  transaction_timestamp() - interval '1 minute'
);
INSERT INTO fixture_0112_exports
SELECT 'future_boundary', app_data.prepare_personal_target_pii_export_v1(
  'https://synthetic-0112.example.test', 'owner',
  (SELECT project_id FROM fixture_0112_owner_context),
  transaction_timestamp() + interval '60 seconds'
);
INSERT INTO fixture_0112_exports
SELECT 'age_inside_boundary', app_data.prepare_personal_target_pii_export_v1(
  'https://synthetic-0112.example.test', 'owner',
  (SELECT project_id FROM fixture_0112_owner_context),
  transaction_timestamp() - interval '15 minutes' + interval '1 millisecond'
);
RESET ROLE;

DO $canonical$
DECLARE
  actual_bytes bytea;
  actual_text text;
  export_document jsonb;
  event_id uuid;
  exported_at_text text;
  expected_text text;
  audit_row app_private.personal_target_pii_export_events%ROWTYPE;
BEGIN
  SELECT export_bytes INTO STRICT actual_bytes
  FROM fixture_0112_exports WHERE case_name = 'canonical';
  actual_text := convert_from(actual_bytes, 'UTF8');
  export_document := actual_text::jsonb;
  event_id := (export_document->>'export_event_id')::uuid;
  exported_at_text := export_document->>'exported_at_utc';

  expected_text :=
    '{"export_contract_id":"personal_promotion_target_pii_export_v1"'
    || ',"export_event_id":' || to_json(event_id::text)::text
    || ',"exported_at_utc":' || to_json(exported_at_text)::text
    || ',"targets":['
    || '{"target_type":"person","display_name":"SORT_EARLIER_SENTINEL"'
    || ',"phone":null,"email":null}'
    || ',{"target_type":"person","display_name":'
    || to_json(E'张三 "A" \\ 路\n下一行\t😀'::text)::text
    || ',"phone":"+1 312 555 0112","email":null}'
    || ',{"target_type":"institution","display_name":"  原值保留  "'
    || ',"phone":null,"email":"Case@Example.TEST "}]}' ;

  IF actual_bytes <> convert_to(expected_text, 'UTF8')
    OR actual_text LIKE '%' || chr(10)
    OR actual_text LIKE '%' || chr(13)
    OR actual_text LIKE '%: %'
    OR actual_text LIKE '%, %'
    OR exported_at_text !~
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
    OR jsonb_array_length(export_document->'targets') <> 3
  THEN
    RAISE EXCEPTION 'personal target PII export bytes are not canonical';
  END IF;

  SELECT event.* INTO STRICT audit_row
  FROM app_private.personal_target_pii_export_events AS event
  WHERE event.export_event_id = event_id;
  IF audit_row.actor_app_user_id <>
      (SELECT app_user_id FROM fixture_0112_owner_context)
    OR audit_row.workspace_id <>
      (SELECT workspace_id FROM fixture_0112_owner_context)
    OR audit_row.export_contract_id <>
      'personal_promotion_target_pii_export_v1'
    OR audit_row.authentication_method <> 'password'
    OR audit_row.authenticated_at_utc <>
      transaction_timestamp() - interval '1 minute'
    OR audit_row.result <> 'prepared'
    OR audit_row.target_count <> 3
    OR audit_row.byte_count <> octet_length(actual_bytes)
    OR to_char(
      audit_row.prepared_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ) <> exported_at_text
  THEN
    RAISE EXCEPTION 'personal target PII export audit is not bound to returned bytes';
  END IF;

  IF actual_text ~ 'ENDED_ASSIGNMENT_SENTINEL|OTHER_ASSIGNEE_SENTINEL|OTHER_WORKSPACE_SENTINEL'
    OR EXISTS (
      SELECT 1
      FROM app_private.personal_target_pii_export_events AS event
      WHERE to_jsonb(event)::text ~
        '张三|原值保留|SORT_EARLIER|312 555|Example.TEST|00000000-0112-4000-8000-00000000000[1-7]'
    )
  THEN
    RAISE EXCEPTION 'personal target PII export leaked excluded rows or values into audit';
  END IF;

  SELECT convert_from(export_bytes, 'UTF8')::jsonb INTO STRICT export_document
  FROM fixture_0112_exports WHERE case_name = 'empty';
  IF export_document->'targets' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'empty personal target PII export was not a valid empty file';
  END IF;

  IF (SELECT count(*)
      FROM app_private.personal_target_pii_export_events
      WHERE actor_app_user_id IN (
        (SELECT app_user_id FROM fixture_0112_owner_context),
        (SELECT app_user_id FROM fixture_0112_other_context)
      )) <> 4
    OR (SELECT count(DISTINCT export_event_id)
        FROM app_private.personal_target_pii_export_events
        WHERE actor_app_user_id IN (
          (SELECT app_user_id FROM fixture_0112_owner_context),
          (SELECT app_user_id FROM fixture_0112_other_context)
        )) <> 4
    OR (SELECT count(*)
        FROM app_private.personal_target_pii_export_events
        WHERE actor_app_user_id =
          (SELECT app_user_id FROM fixture_0112_owner_context)) <> 3
  THEN
    RAISE EXCEPTION 'successful personal target PII export retries did not append distinct events';
  END IF;
END
$canonical$;

CREATE TEMP TABLE fixture_0112_audit_baseline ON COMMIT DROP AS
SELECT count(*) AS event_count
FROM app_private.personal_target_pii_export_events;

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0112_inactive_context);
UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp()
WHERE workspace_id = (SELECT workspace_id FROM fixture_0112_deleted_context);

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_failure('22023', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'owner',
  (SELECT project_id FROM fixture_0112_owner_context),
  transaction_timestamp() + interval '60.001 seconds'
));
SELECT pg_temp.expect_failure('22023', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'owner',
  (SELECT project_id FROM fixture_0112_owner_context),
  transaction_timestamp() - interval '15 minutes'
));
SELECT pg_temp.expect_failure('22023', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'owner',
  (SELECT project_id FROM fixture_0112_owner_context), 'infinity'
));
SELECT pg_temp.expect_failure('42501', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'unknown-owner',
  (SELECT project_id FROM fixture_0112_owner_context), transaction_timestamp()
));
SELECT pg_temp.expect_failure('42501', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'inactive-owner',
  (SELECT project_id FROM fixture_0112_inactive_context), transaction_timestamp()
));
SELECT pg_temp.expect_failure('42501', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'deleted-owner',
  (SELECT project_id FROM fixture_0112_deleted_context), transaction_timestamp()
));
SELECT pg_temp.expect_failure('42501', format(
  'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
  'https://synthetic-0112.example.test', 'owner',
  '00000000-0112-4000-8000-000000000099', transaction_timestamp()
));
SELECT pg_temp.expect_failure(
  '42501',
  format(
    'SELECT app_data.prepare_personal_target_pii_export_v1(%L,%L,%L::uuid,%L::timestamptz)',
    'https://synthetic-0112.example.test', 'owner ',
    (SELECT project_id FROM fixture_0112_owner_context), transaction_timestamp()
  ),
  '张三'
);
RESET ROLE;

DO $failures$
DECLARE
  event_id uuid;
BEGIN
  IF (SELECT count(*) FROM app_private.personal_target_pii_export_events) <>
      (SELECT event_count FROM fixture_0112_audit_baseline)
  THEN
    RAISE EXCEPTION 'failed personal target PII exports wrote success audit';
  END IF;

  SELECT export_event_id INTO STRICT event_id
  FROM app_private.personal_target_pii_export_events
  ORDER BY prepared_at_utc, export_event_id
  LIMIT 1;
  BEGIN
    UPDATE app_private.personal_target_pii_export_events
    SET target_count = target_count
    WHERE export_event_id = event_id;
    RAISE EXCEPTION 'personal target PII export audit accepted update';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.personal_target_pii_export_events
    WHERE export_event_id = event_id;
    RAISE EXCEPTION 'personal target PII export audit accepted delete';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END
$failures$;

ROLLBACK;
