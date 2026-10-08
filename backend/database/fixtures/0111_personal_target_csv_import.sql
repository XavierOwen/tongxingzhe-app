\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0111_owner_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0111.example.test', 'owner'
);
CREATE TEMP TABLE fixture_0111_other_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0111.example.test', 'other-owner'
);
CREATE TEMP TABLE fixture_0111_inactive_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0111.example.test', 'inactive-owner'
);
CREATE TEMP TABLE fixture_0111_deleted_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0111.example.test', 'deleted-owner'
);

CREATE TEMP TABLE fixture_0111_previews (
  case_name text PRIMARY KEY,
  contract_id text,
  preview_id uuid,
  row_count integer,
  hinted_rows integer[],
  previewed_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0111_confirms (
  case_name text PRIMARY KEY,
  contract_id text,
  preview_id uuid,
  request_id uuid,
  outcome text,
  row_count integer,
  hint_count integer,
  created_count integer,
  created_targets jsonb,
  completed_at_utc timestamptz
) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0111_request_baseline (
  target_count bigint,
  claim_count bigint,
  audit_count bigint
) ON COMMIT DROP;
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
  IF actual_state IS NULL OR actual_state <> expected_state THEN
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
  fixture_0111_owner_context,
  fixture_0111_other_context,
  fixture_0111_inactive_context,
  fixture_0111_deleted_context,
  fixture_0111_previews,
  fixture_0111_confirms
TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0111_previews
SELECT 'empty', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context), '[]'::jsonb
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'five_hundred', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT jsonb_agg(jsonb_build_object(
    'target_type', 'person',
    'display_name', 'CSV_BULK_' || lpad(row_number::text, 3, '0'),
    'phone', NULL,
    'email', NULL
  ) ORDER BY row_number) FROM generate_series(1, 500) AS row_number)
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'canonical', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','  CSV_TRIMMED  ','phone','  ','email',''),
    jsonb_build_object('target_type','institution','display_name',repeat('N',200),
      'phone',repeat('P',80),'email',repeat('e',309) || '@' || repeat('d',6) || '.com')
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'skip_create', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_SKIP_ROW','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','institution','display_name','CSV_CREATE_ROW','phone',NULL,'email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'row_drift', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_ROW_DRIFT_A','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_ROW_DRIFT_B','phone',NULL,'email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'order_drift', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_ORDER_A','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_ORDER_B','phone',NULL,'email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'selection', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_SELECTION_PHONE_A','phone','+1-555-0113','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_SELECTION_PHONE_B','phone',' +1-555-0113 ','email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'invalid_actions', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_INVALID_ACTION_A','phone','+1-555-0114','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_INVALID_ACTION_B','phone','+1-555-0114','email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'atomic', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_ATOMIC_FIRST','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_ATOMIC_FAILURE','phone',NULL,'email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_confirms
SELECT 'empty', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'empty'),
  '00000000-0111-6000-8000-000000000001',
  '[]'::jsonb, '[]'::jsonb
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'five_hundred', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'five_hundred'),
  '00000000-0111-6000-8000-000000000002',
  (SELECT jsonb_agg(jsonb_build_object(
    'target_type', 'person',
    'display_name', 'CSV_BULK_' || lpad(row_number::text, 3, '0'),
    'phone', NULL,
    'email', NULL
  ) ORDER BY row_number) FROM generate_series(1, 500) AS row_number),
  (SELECT jsonb_agg(to_jsonb('skip'::text) ORDER BY row_number)
   FROM generate_series(1, 500) AS row_number)
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'canonical', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'canonical'),
  '00000000-0111-6000-8000-000000000003',
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_TRIMMED','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','institution','display_name',repeat('N',200),
      'phone',repeat('P',80),'email',repeat('e',309) || '@' || repeat('d',6) || '.com')
  ),
  '["create","create"]'::jsonb
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'skip_create', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'skip_create'),
  '00000000-0111-6000-8000-000000000004',
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_SKIP_ROW','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','institution','display_name','CSV_CREATE_ROW','phone',NULL,'email',NULL)
  ),
  '["skip","create"]'::jsonb
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'selection', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'selection'),
  '00000000-0111-6000-8000-000000000005',
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_SELECTION_PHONE_A','phone','+1-555-0113','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_SELECTION_PHONE_B','phone','+1-555-0113','email',NULL)
  ),
  '["skip","create_separate"]'::jsonb
) AS result;

INSERT INTO fixture_0111_previews
SELECT 'confirm_owner_scope', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(jsonb_build_object(
    'target_type','person','display_name','CSV_CONFIRM_OWNER_SCOPE',
    'phone',NULL,'email',NULL
  ))
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'confirm_inactive_identity', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'inactive-owner',
  (SELECT project_id FROM fixture_0111_inactive_context),
  jsonb_build_array(jsonb_build_object(
    'target_type','person','display_name','CSV_CONFIRM_INACTIVE_IDENTITY',
    'phone',NULL,'email',NULL
  ))
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'confirm_deleted_identity', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'deleted-owner',
  (SELECT project_id FROM fixture_0111_deleted_context),
  jsonb_build_array(jsonb_build_object(
    'target_type','person','display_name','CSV_CONFIRM_DELETED_IDENTITY',
    'phone',NULL,'email',NULL
  ))
) AS preview;

RESET ROLE;

INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name, phone, email,
  created_by_app_user_id
)
SELECT
  '00000000-0111-5000-8000-000000000001'::uuid, workspace_id, 'person',
  'CSV_ASSIGNED_PHONE', '+1-555-0101', NULL, app_user_id
FROM fixture_0111_owner_context
UNION ALL
SELECT
  '00000000-0111-5000-8000-000000000002'::uuid, workspace_id, 'person',
  'CSV_ASSIGNED_EMAIL', NULL, 'assigned@example.test', app_user_id
FROM fixture_0111_owner_context
UNION ALL
SELECT
  '00000000-0111-5000-8000-000000000003'::uuid, workspace_id, 'person',
  'CSV_UNASSIGNED_ONLY', '+1-555-0103', NULL, app_user_id
FROM fixture_0111_owner_context
UNION ALL
SELECT
  '00000000-0111-5000-8000-000000000004'::uuid, workspace_id, 'person',
  'CSV_OTHER_SPACE_ONLY', '+1-555-0104', NULL, app_user_id
FROM fixture_0111_other_context;

INSERT INTO app_data.promotion_target_assignments (
  promotion_target_id, app_user_id, assigned_by_app_user_id
)
SELECT target.promotion_target_id, context.app_user_id, context.app_user_id
FROM (VALUES
  ('00000000-0111-5000-8000-000000000001'::uuid,
    (SELECT app_user_id FROM fixture_0111_owner_context)),
  ('00000000-0111-5000-8000-000000000002'::uuid,
    (SELECT app_user_id FROM fixture_0111_owner_context)),
  ('00000000-0111-5000-8000-000000000004'::uuid,
    (SELECT app_user_id FROM fixture_0111_other_context))
) AS target(promotion_target_id, app_user_id)
JOIN app_data.app_users AS context USING (app_user_id);

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0111_previews
SELECT 'hints', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_HINT_PHONE_A','phone',' +1-555-0111 ','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_HINT_PHONE_B','phone','+1-555-0111','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_HINT_EMAIL_A','phone',NULL,'email',' Case@Example.test '),
    jsonb_build_object('target_type','person','display_name','CSV_HINT_EMAIL_B','phone',NULL,'email','case@example.test'),
    jsonb_build_object('target_type','person','display_name','CSV_ASSIGNED_PHONE','phone','+1-555-0101','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_ASSIGNED_EMAIL','phone',NULL,'email','assigned@example.test'),
    jsonb_build_object('target_type','person','display_name','CSV_ASSIGNED_PHONE','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_UNASSIGNED_ONLY','phone','+1-555-0103','email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_OTHER_SPACE_ONLY','phone','+1-555-0104','email',NULL)
  )
) AS preview;

INSERT INTO fixture_0111_previews
SELECT 'hint_drift', preview.*
FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_HINT_DRIFT_NEW','phone','+1-555-0112','email',NULL)
  )
) AS preview;

RESET ROLE;

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0111_inactive_context);
UPDATE app_data.workspaces
SET deleted_at = clock_timestamp()
WHERE workspace_id = (SELECT workspace_id FROM fixture_0111_deleted_context);
INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
SELECT
  '00000000-0111-7000-8000-000000000001', workspace_id,
  'CSV archived project', 'archived', false
FROM fixture_0111_owner_context;

INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name, phone, email,
  created_by_app_user_id
)
SELECT
  '00000000-0111-5000-8000-000000000005', workspace_id, 'person',
  'CSV_HINT_DRIFT_EXISTING', '+1-555-0112', NULL, app_user_id
FROM fixture_0111_owner_context;
INSERT INTO app_data.promotion_target_assignments (
  promotion_target_id, app_user_id, assigned_by_app_user_id
)
SELECT
  '00000000-0111-5000-8000-000000000005', app_user_id, app_user_id
FROM fixture_0111_owner_context;

-- Directly seed an expired receipt; never UPDATE an immutable preview row.
INSERT INTO app_private.personal_target_csv_import_previews (
  preview_id, contract_id, actor_app_user_id, workspace_id, project_id,
  rows_fingerprint, row_count, hinted_rows, previewed_at_utc, expires_at_utc
)
SELECT
  '00000000-0111-8000-8000-000000000001',
  'personal-target-csv-import-preview:v1',
  owner.app_user_id, owner.workspace_id, owner.project_id,
  app_private.personal_target_csv_import_fingerprint_v1(
    '00000000-0111-8000-8000-000000000001',
    app_private.canonical_personal_target_csv_import_rows_v1(
      jsonb_build_array(jsonb_build_object(
        'target_type','person','display_name','CSV_EXPIRED','phone',NULL,'email',NULL
      ))
    )
  ),
  1,
  ARRAY[]::integer[],
  stamp.as_of_utc - interval '15 minutes',
  stamp.as_of_utc
FROM fixture_0111_owner_context AS owner
CROSS JOIN (SELECT statement_timestamp() AS as_of_utc) AS stamp;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0111_confirms
SELECT 'expired', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  '00000000-0111-8000-8000-000000000001',
  '00000000-0111-6000-8000-000000000006',
  jsonb_build_array(jsonb_build_object(
    'target_type','person','display_name','CSV_EXPIRED','phone',NULL,'email',NULL
  )),
  '["create"]'::jsonb
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'row_drift', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'row_drift'),
  '00000000-0111-6000-8000-000000000007',
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_ROW_DRIFT_CHANGED','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_ROW_DRIFT_B','phone',NULL,'email',NULL)
  ),
  '["create","create"]'::jsonb
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'order_drift', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'order_drift'),
  '00000000-0111-6000-8000-000000000008',
  jsonb_build_array(
    jsonb_build_object('target_type','person','display_name','CSV_ORDER_B','phone',NULL,'email',NULL),
    jsonb_build_object('target_type','person','display_name','CSV_ORDER_A','phone',NULL,'email',NULL)
  ),
  '["create","create"]'::jsonb
) AS result;

INSERT INTO fixture_0111_confirms
SELECT 'hint_drift', result.*
FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0111.example.test', 'owner',
  (SELECT project_id FROM fixture_0111_owner_context),
  (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'hint_drift'),
  '00000000-0111-6000-8000-000000000009',
  jsonb_build_array(jsonb_build_object(
    'target_type','person','display_name','CSV_HINT_DRIFT_NEW','phone','+1-555-0112','email',NULL
  )),
  '["create"]'::jsonb
) AS result;

RESET ROLE;
INSERT INTO fixture_0111_request_baseline
SELECT
  (SELECT count(*) FROM app_data.promotion_targets),
  (SELECT count(*) FROM app_private.personal_target_csv_import_request_claims
    WHERE request_id = '00000000-0111-6000-8000-000000000003'),
  (SELECT count(*) FROM app_private.personal_target_csv_import_audit_events
    WHERE request_id = '00000000-0111-6000-8000-000000000003');

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_failure(
  '23505',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'canonical'),
    '00000000-0111-6000-8000-000000000003',
    jsonb_build_array(
      jsonb_build_object('target_type','person','display_name','CSV_SENTINEL_REQUEST_DRIFT','phone',NULL,'email',NULL),
      jsonb_build_object('target_type','institution','display_name',repeat('N',200),
        'phone',repeat('P',80),'email',repeat('e',309) || '@' || repeat('d',6) || '.com')
    )::text,
    '["create","create"]'
  ),
  'CSV_SENTINEL_REQUEST_DRIFT'
);
SELECT pg_temp.expect_failure(
  '23505',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'canonical'),
    '00000000-0111-6000-8000-000000000003',
    jsonb_build_array(
      jsonb_build_object('target_type','person','display_name','CSV_TRIMMED','phone',NULL,'email',NULL),
      jsonb_build_object('target_type','institution','display_name',repeat('N',200),
        'phone',repeat('P',80),'email',repeat('e',309) || '@' || repeat('d',6) || '.com')
    )::text,
    '["skip","create"]'
  ),
  NULL
);

RESET ROLE;
CREATE FUNCTION app_private.fixture_0111_reject_target_insert()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NEW.display_name = 'CSV_ATOMIC_FAILURE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'synthetic target insert failure';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0111_reject_target_insert
BEFORE INSERT ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION app_private.fixture_0111_reject_target_insert();

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_failure(
  '23514',
  format($query$
    SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
      %L, %L, %L, %L, %L, %L::jsonb, %L::jsonb
    )
  $query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'atomic'),
    '00000000-0111-6000-8000-000000000010',
    jsonb_build_array(
      jsonb_build_object('target_type','person','display_name','CSV_ATOMIC_FIRST','phone',NULL,'email',NULL),
      jsonb_build_object('target_type','person','display_name','CSV_ATOMIC_FAILURE','phone',NULL,'email',NULL)
    )::text,
    '["create","create"]'
  ),
  NULL
);
RESET ROLE;
DROP TRIGGER fixture_0111_reject_target_insert ON app_data.promotion_targets;
DROP FUNCTION app_private.fixture_0111_reject_target_insert();

SELECT pg_temp.expect_failure(
  '22023',
  format($query$
    SELECT * FROM app_data.preview_personal_target_csv_import_v1(
      %L, %L, %L, %L::jsonb
    )
  $query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_SENTINEL_PRIVATE_ERROR_' || repeat('x',201),
      'phone',NULL,'email',NULL
    ))::text
  ),
  'CSV_SENTINEL_PRIVATE_ERROR'
);

SELECT pg_temp.expect_failure(
  '22023',
  format($query$
    SELECT * FROM app_data.preview_personal_target_csv_import_v1(
      %L, %L, %L, (SELECT jsonb_agg(jsonb_build_object(
        'target_type','person','display_name','CSV_OVER_500_' || row_number,
        'phone',NULL,'email',NULL
      ) ORDER BY row_number) FROM generate_series(1,501) AS row_number)
    )
  $query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context)
  ),
  NULL
);

SELECT pg_temp.expect_failure(
  '22023',
  format($query$
    SELECT * FROM app_data.preview_personal_target_csv_import_v1(
      %L, %L, %L, %L::jsonb
    )
  $query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_EXTRA_KEY','phone',NULL,
      'email',NULL,'extra','CSV_SENTINEL_EXTRA'
    ))::text
  ),
  'CSV_SENTINEL_EXTRA'
);

SELECT pg_temp.expect_failure(
  '22023',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_PHONE_BOUNDARY','phone',repeat('P',81),'email',NULL
    ))::text
  ),
  'CSV_PHONE_BOUNDARY'
);
SELECT pg_temp.expect_failure(
  '22023',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_EMAIL_BOUNDARY','phone',NULL,
      'email','CSV_SENTINEL_EMAIL_' || repeat('e',297) || '@x.com'
    ))::text
  ),
  'CSV_SENTINEL_EMAIL'
);
SELECT pg_temp.expect_failure(
  '22023',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','   ','phone',NULL,'email',NULL
    ))::text
  ),
  NULL
);
SELECT pg_temp.expect_failure(
  '22023',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    jsonb_build_array(jsonb_build_object(
      'target_type','CSV_SENTINEL_TYPE','display_name','CSV_INVALID_TYPE','phone',NULL,'email',NULL
    ))::text
  ),
  'CSV_SENTINEL_TYPE'
);

SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, '[]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'missing-identity',
    (SELECT project_id FROM fixture_0111_owner_context)
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, '[]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'inactive-owner',
    (SELECT project_id FROM fixture_0111_inactive_context)
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, '[]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'deleted-owner',
    (SELECT project_id FROM fixture_0111_deleted_context)
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, '[]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_other_context)
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.preview_personal_target_csv_import_v1(
    %L, %L, %L, '[]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    '00000000-0111-7000-8000-000000000001'
  ), NULL
);

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, '["create"]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'missing-confirm-identity',
    (SELECT project_id FROM fixture_0111_owner_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'confirm_owner_scope'),
    '00000000-0111-6000-8000-000000000012',
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_CONFIRM_OWNER_SCOPE',
      'phone',NULL,'email',NULL
    ))::text
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, '["create"]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'inactive-owner',
    (SELECT project_id FROM fixture_0111_inactive_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'confirm_inactive_identity'),
    '00000000-0111-6000-8000-000000000013',
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_CONFIRM_INACTIVE_IDENTITY',
      'phone',NULL,'email',NULL
    ))::text
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, '["create"]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'deleted-owner',
    (SELECT project_id FROM fixture_0111_deleted_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'confirm_deleted_identity'),
    '00000000-0111-6000-8000-000000000014',
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_CONFIRM_DELETED_IDENTITY',
      'phone',NULL,'email',NULL
    ))::text
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, '["create"]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_other_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'confirm_owner_scope'),
    '00000000-0111-6000-8000-000000000015',
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_CONFIRM_OWNER_SCOPE',
      'phone',NULL,'email',NULL
    ))::text
  ), NULL
);
SELECT pg_temp.expect_failure(
  '42501',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, '["create"]'::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    '00000000-0111-7000-8000-000000000001',
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'confirm_owner_scope'),
    '00000000-0111-6000-8000-000000000016',
    jsonb_build_array(jsonb_build_object(
      'target_type','person','display_name','CSV_CONFIRM_OWNER_SCOPE',
      'phone',NULL,'email',NULL
    ))::text
  ), NULL
);
RESET ROLE;

SELECT pg_temp.expect_failure(
  '22023',
  format($query$SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
    %L, %L, %L, %L, %L, %L::jsonb, %L::jsonb)$query$,
    'https://synthetic-0111.example.test', 'owner',
    (SELECT project_id FROM fixture_0111_owner_context),
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'invalid_actions'),
    '00000000-0111-6000-8000-000000000011',
    jsonb_build_array(
      jsonb_build_object('target_type','person','display_name','CSV_INVALID_ACTION_A','phone','+1-555-0114','email',NULL),
      jsonb_build_object('target_type','person','display_name','CSV_INVALID_ACTION_B','phone','+1-555-0114','email',NULL)
    )::text,
    '["create","skip"]'
  ), NULL
);

RESET ROLE;

SELECT pg_temp.expect_failure(
  '55000',
  format($query$UPDATE app_private.personal_target_csv_import_previews
    SET row_count = row_count WHERE preview_id = %L$query$,
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'empty')
  ), NULL
);
SELECT pg_temp.expect_failure(
  '55000',
  format($query$DELETE FROM app_private.personal_target_csv_import_previews
    WHERE preview_id = %L$query$,
    (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'empty')
  ), NULL
);
SELECT pg_temp.expect_failure(
  '55000',
  format($query$UPDATE app_private.personal_target_csv_import_request_claims
    SET outcome = outcome WHERE request_id = %L$query$,
    '00000000-0111-6000-8000-000000000003'
  ), NULL
);
SELECT pg_temp.expect_failure(
  '55000',
  format($query$DELETE FROM app_private.personal_target_csv_import_request_claims
    WHERE request_id = %L$query$,
    '00000000-0111-6000-8000-000000000003'
  ), NULL
);
SELECT pg_temp.expect_failure(
  '55000',
  format($query$UPDATE app_private.personal_target_csv_import_audit_events
    SET outcome = outcome WHERE request_id = %L$query$,
    '00000000-0111-6000-8000-000000000003'
  ), NULL
);
SELECT pg_temp.expect_failure(
  '55000',
  format($query$DELETE FROM app_private.personal_target_csv_import_audit_events
    WHERE request_id = %L$query$,
    '00000000-0111-6000-8000-000000000003'
  ), NULL
);

DO $assertions$
DECLARE
  boundary_ids uuid[];
  selected_ids uuid[];
  one_created_id uuid;
  private_documents text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.list_personal_project_contexts(
      'https://synthetic-0111.example.test', 'owner'
    ) AS context
    WHERE context.is_current
      AND context.capabilities @> ARRAY['import_target_pii']::text[]
  ) THEN
    RAISE EXCEPTION '0111 personal capability is missing from trusted context';
  END IF;

  IF (SELECT contract_id FROM fixture_0111_previews WHERE case_name = 'empty')
      IS DISTINCT FROM 'personal-target-csv-import-preview:v1'
    OR (SELECT row_count FROM fixture_0111_previews WHERE case_name = 'empty') <> 0
    OR (SELECT hinted_rows FROM fixture_0111_previews WHERE case_name = 'empty')
      IS DISTINCT FROM ARRAY[]::integer[]
    OR NOT EXISTS (
      SELECT 1 FROM fixture_0111_previews
      WHERE case_name = 'empty'
        AND expires_at_utc = previewed_at_utc + interval '15 minutes'
    )
  THEN
    RAISE EXCEPTION '0111 empty preview or expiry receipt is incorrect';
  END IF;

  IF (SELECT row_count FROM fixture_0111_previews WHERE case_name = 'five_hundred') <> 500
    OR (SELECT hinted_rows FROM fixture_0111_previews WHERE case_name = 'five_hundred')
      IS DISTINCT FROM ARRAY[]::integer[]
  THEN
    RAISE EXCEPTION '0111 500-row preview boundary failed';
  END IF;

  IF (SELECT hinted_rows FROM fixture_0111_previews WHERE case_name = 'hints')
      IS DISTINCT FROM ARRAY[1,2,3,4,5,6]::integer[]
  THEN
    RAISE EXCEPTION '0111 exact same-file/assigned hints or exclusion rules failed';
  END IF;

  IF (SELECT outcome FROM fixture_0111_confirms WHERE case_name = 'empty') <> 'confirmed'
    OR (SELECT row_count FROM fixture_0111_confirms WHERE case_name = 'empty') <> 0
    OR (SELECT outcome FROM fixture_0111_confirms WHERE case_name = 'five_hundred') <> 'confirmed'
    OR (SELECT created_count FROM fixture_0111_confirms WHERE case_name = 'five_hundred') <> 0
  THEN
    RAISE EXCEPTION '0111 empty or 500-row confirmation failed';
  END IF;

  SELECT array_agg((target.value->>'target_id')::uuid ORDER BY (target.value->>'row_number')::integer)
  INTO boundary_ids
  FROM fixture_0111_confirms AS result
  CROSS JOIN LATERAL jsonb_array_elements(result.created_targets) AS target(value)
  WHERE result.case_name = 'canonical';
  IF cardinality(boundary_ids) <> 2
    OR (SELECT created_count FROM fixture_0111_confirms WHERE case_name = 'canonical') <> 2
    OR EXISTS (
      SELECT 1
      FROM app_data.promotion_targets AS target
      WHERE target.promotion_target_id = boundary_ids[1]
        AND (target.target_type <> 'person' OR target.display_name <> 'CSV_TRIMMED'
          OR target.phone IS NOT NULL OR target.email IS NOT NULL)
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.promotion_targets AS target
      WHERE target.promotion_target_id = boundary_ids[2]
        AND target.target_type = 'institution'
        AND length(target.display_name) = 200
        AND length(target.phone) = 80
        AND length(target.email) = 320
    )
  THEN
    RAISE EXCEPTION '0111 canonical trim/null or maximum field boundaries failed';
  END IF;

  SELECT (target.value->>'target_id')::uuid
  INTO one_created_id
  FROM fixture_0111_confirms AS result
  CROSS JOIN LATERAL jsonb_array_elements(result.created_targets) AS target(value)
  WHERE result.case_name = 'skip_create';
  IF (SELECT created_count FROM fixture_0111_confirms WHERE case_name = 'skip_create') <> 1
    OR (SELECT target.value->>'row_number'
        FROM fixture_0111_confirms AS result
        CROSS JOIN LATERAL jsonb_array_elements(result.created_targets) AS target(value)
        WHERE result.case_name = 'skip_create') <> '2'
    OR EXISTS (
      SELECT 1 FROM app_data.promotion_targets
      WHERE display_name = 'CSV_SKIP_ROW'
    )
  THEN
    RAISE EXCEPTION '0111 skip/create selection failed';
  END IF;

  SELECT array_agg((target.value->>'target_id')::uuid ORDER BY (target.value->>'row_number')::integer)
  INTO selected_ids
  FROM fixture_0111_confirms AS result
  CROSS JOIN LATERAL jsonb_array_elements(result.created_targets) AS target(value)
  WHERE result.case_name = 'selection';
  IF cardinality(selected_ids) <> 1
    OR (SELECT target.value->>'row_number'
        FROM fixture_0111_confirms AS result
        CROSS JOIN LATERAL jsonb_array_elements(result.created_targets) AS target(value)
        WHERE result.case_name = 'selection') <> '2'
  THEN
    RAISE EXCEPTION '0111 hinted skip/create_separate selection failed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.promotion_targets AS target
    JOIN app_data.promotion_target_assignments AS assignment
      ON assignment.promotion_target_id = target.promotion_target_id
     AND assignment.ended_at IS NULL
    JOIN fixture_0111_owner_context AS owner
      ON owner.workspace_id = target.workspace_id
     AND owner.app_user_id = target.created_by_app_user_id
     AND owner.app_user_id = assignment.app_user_id
     AND owner.app_user_id = assignment.assigned_by_app_user_id
    WHERE target.promotion_target_id IN (SELECT unnest(boundary_ids) UNION SELECT unnest(selected_ids))
      AND (SELECT count(*) FROM app_data.promotion_target_access_events AS event
        WHERE event.promotion_target_id = target.promotion_target_id
          AND event.action = 'created'
          AND event.actor_app_user_id = owner.app_user_id
          AND event.workspace_id = owner.workspace_id) <> 1
  ) OR EXISTS (
    SELECT 1
    FROM unnest(boundary_ids || selected_ids) AS target_id
    WHERE NOT EXISTS (
      SELECT 1 FROM app_data.promotion_targets AS target
      JOIN app_data.promotion_target_assignments AS assignment
        ON assignment.promotion_target_id = target.promotion_target_id
       AND assignment.ended_at IS NULL
      WHERE target.promotion_target_id = target_id
    )
  ) THEN
    RAISE EXCEPTION '0111 creator, initial assignment, or created access audit failed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM fixture_0111_confirms
    WHERE case_name IN ('expired','row_drift','order_drift','hint_drift')
      AND outcome <> 'stale_preview'
  ) OR EXISTS (
    SELECT 1 FROM app_data.promotion_targets
    WHERE display_name IN (
      'CSV_EXPIRED','CSV_ROW_DRIFT_A','CSV_ROW_DRIFT_B',
      'CSV_ROW_DRIFT_CHANGED','CSV_ORDER_A','CSV_ORDER_B','CSV_HINT_DRIFT_NEW'
    )
  ) THEN
    RAISE EXCEPTION '0111 expired or changed preview wrote an object';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_request_claims AS claim
    WHERE claim.request_id IN (
      '00000000-0111-6000-8000-000000000006',
      '00000000-0111-6000-8000-000000000007',
      '00000000-0111-6000-8000-000000000008',
      '00000000-0111-6000-8000-000000000009'
    ) AND claim.outcome <> 'stale_preview'
  ) THEN
    RAISE EXCEPTION '0111 stale receipts were not recorded as value-free outcomes';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.promotion_targets AS target
    WHERE target.display_name IN ('CSV_ATOMIC_FIRST','CSV_ATOMIC_FAILURE')
  ) OR EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_request_claims AS claim
    WHERE claim.request_id = '00000000-0111-6000-8000-000000000010'
  ) OR EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_audit_events AS event
    WHERE event.request_id = '00000000-0111-6000-8000-000000000010'
  ) THEN
    RAISE EXCEPTION '0111 failed batch left partial targets, claim, or audit';
  END IF;

  IF (SELECT count(*) FROM app_data.promotion_targets)
      IS DISTINCT FROM (SELECT target_count FROM fixture_0111_request_baseline)
    OR (SELECT count(*) FROM app_private.personal_target_csv_import_request_claims
      WHERE request_id = '00000000-0111-6000-8000-000000000003')
      IS DISTINCT FROM (SELECT claim_count FROM fixture_0111_request_baseline)
    OR (SELECT count(*) FROM app_private.personal_target_csv_import_audit_events
      WHERE request_id = '00000000-0111-6000-8000-000000000003')
      IS DISTINCT FROM (SELECT audit_count FROM fixture_0111_request_baseline)
  THEN
    RAISE EXCEPTION '0111 request drift changed claim, audit, or object counts';
  END IF;

  IF EXISTS (
    SELECT 1 FROM app_data.promotion_targets
    WHERE display_name IN (
      'CSV_CONFIRM_OWNER_SCOPE',
      'CSV_CONFIRM_INACTIVE_IDENTITY',
      'CSV_CONFIRM_DELETED_IDENTITY'
    )
  ) OR EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_request_claims
    WHERE request_id IN (
      '00000000-0111-6000-8000-000000000012',
      '00000000-0111-6000-8000-000000000013',
      '00000000-0111-6000-8000-000000000014',
      '00000000-0111-6000-8000-000000000015',
      '00000000-0111-6000-8000-000000000016'
    )
  ) OR EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_audit_events
    WHERE request_id IN (
      '00000000-0111-6000-8000-000000000012',
      '00000000-0111-6000-8000-000000000013',
      '00000000-0111-6000-8000-000000000014',
      '00000000-0111-6000-8000-000000000015',
      '00000000-0111-6000-8000-000000000016'
    )
  ) THEN
    RAISE EXCEPTION '0111 rejected confirm wrote targets, claims, or audit';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_audit_events AS event
    WHERE event.preview_id = (SELECT preview_id FROM fixture_0111_previews WHERE case_name = 'canonical')
      AND event.phase = 'preview'
      AND event.request_id IS NULL
      AND event.source_kind = 'csv'
      AND event.created_count = 0
      AND event.outcome = 'previewed'
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_audit_events AS event
    WHERE event.request_id = '00000000-0111-6000-8000-000000000003'
      AND event.phase = 'confirm'
      AND event.outcome = 'confirmed'
      AND event.row_count = 2
      AND event.hint_count = 0
      AND event.created_count = 2
      AND event.source_kind = 'csv'
  ) THEN
    RAISE EXCEPTION '0111 value-free preview/confirm audits are incomplete';
  END IF;

  SELECT string_agg(relation_row::text, ' ')
  INTO private_documents
  FROM (
    SELECT to_jsonb(row_value) AS relation_row
    FROM app_private.personal_target_csv_import_previews AS row_value
    UNION ALL
    SELECT to_jsonb(row_value)
    FROM app_private.personal_target_csv_import_request_claims AS row_value
    UNION ALL
    SELECT to_jsonb(row_value)
    FROM app_private.personal_target_csv_import_audit_events AS row_value
  ) AS private_rows;
  IF private_documents LIKE '%CSV_%'
    OR private_documents LIKE '%+1-555-%'
    OR private_documents LIKE '%@Example.test%'
    OR private_documents LIKE '%assigned@example.test%'
  THEN
    RAISE EXCEPTION '0111 private preview, claim, or audit stored row PII';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_request_claims AS claim
    WHERE claim.actor_app_user_id <> (SELECT app_user_id FROM fixture_0111_owner_context)
      AND claim.request_id IN (
        '00000000-0111-6000-8000-000000000001',
        '00000000-0111-6000-8000-000000000002',
        '00000000-0111-6000-8000-000000000003',
        '00000000-0111-6000-8000-000000000004',
        '00000000-0111-6000-8000-000000000005'
      )
  ) THEN
    RAISE EXCEPTION '0111 confirm used a client-supplied actor';
  END IF;
END
$assertions$;

ROLLBACK;
