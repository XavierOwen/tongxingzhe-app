-- Synthetic private history contributions. Every row and fault trigger rolls back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.assert_0134(condition boolean, label text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0134 %', label; END IF;
END
$function$;
CREATE FUNCTION pg_temp.contribution_state_0134()
RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'previews', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY preview_id), '[]') FROM app_private.personal_history_contribution_previews_v1 t),
    'copies', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY copy_id), '[]') FROM app_private.organization_historical_contact_copies_v1 t),
    'confirmations', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY request_id), '[]') FROM app_private.personal_history_contribution_confirmations_v1 t));
$function$;
CREATE FUNCTION pg_temp.expect_0134_failure(expected_state text, expected_message text, statement text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.contribution_state_0134(); actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state
    OR (expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0134 expected % / %, got % / %', expected_state, expected_message, actual_state, actual_message;
  END IF;
  PERFORM pg_temp.assert_0134(before_state = pg_temp.contribution_state_0134(), 'failure left partial contribution facts');
END
$function$;
CREATE FUNCTION pg_temp.legacy_state_0134()
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; statements text; result jsonb;
BEGIN
  FOR relation IN SELECT schemaname, tablename FROM pg_catalog.pg_tables
    WHERE schemaname IN ('app_data', 'app_private')
      AND NOT (schemaname = 'app_private' AND tablename IN ('personal_history_contribution_previews_v1',
        'organization_historical_contact_copies_v1', 'personal_history_contribution_confirmations_v1'))
    ORDER BY schemaname, tablename
  LOOP
    statements := concat_ws(' UNION ALL ',statements,format('SELECT %L::text AS relation_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) AS contents FROM %I.%I t',
      relation.schemaname || '.' || relation.tablename,relation.schemaname, relation.tablename));
  END LOOP;
  IF statements IS NULL THEN RETURN '{}'::jsonb; END IF;
  EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM (' || statements || ') snapshots' INTO result;
  RETURN result;
END
$function$;

CREATE TEMP TABLE fixture_0134_context AS SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0134.example.test', 'contributor');
CREATE TEMP TABLE fixture_0134_owner AS SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0134.example.test', 'organization-owner');
SELECT pg_temp.assert_0134(result_code = 'accepted', 'owner source seed was rejected')
FROM fixture_0134_owner c, LATERAL app_data.apply_contact_submit_v3(c.app_user_id,
  '0134-owner-source-submit', 1, 'contact.submit.v1', '0134-device', '0134-owner-source', 0,
  jsonb_build_object('contactId', '0134-owner-source', 'workspaceId', c.workspace_id, 'projectId', c.project_id,
    'questionnaireVersionId', c.questionnaire_version_id, 'reason', '0134 owner source',
    'occurredAtUtc', '2025-03-09T07:59:59.123456Z', 'occurredTimeZone', 'UTC', 'channel', 'video_call',
    'location', jsonb_build_object('kind', 'not_applicable'), 'reachCount', 1, 'interestLevel', 2,
    'answers', '[]'::jsonb, 'targetLinks', '[]'::jsonb)) submitted;
CREATE TEMP TABLE fixture_0134_org AS SELECT receipt.* FROM fixture_0134_owner owner,
  LATERAL app_private.create_organization_v1(owner.app_user_id,
    '00000000-0134-1000-8000-000000000001', '0134 target organization') receipt;
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT project_id, organization_workspace_id, '0134 target project' FROM fixture_0134_org CROSS JOIN
  (VALUES ('00000000-0134-2000-8000-000000000001'::uuid),
    ('00000000-0134-2000-8000-000000000002'::uuid)) projects(project_id);
CREATE TEMP TABLE fixture_0134_invitation AS SELECT receipt.* FROM fixture_0134_context c,
  fixture_0134_owner owner, fixture_0134_org org,
  LATERAL app_private.create_organization_directed_account_invitation_v1(owner.app_user_id,
    '00000000-0134-3000-8000-000000000001', org.organization_workspace_id, c.app_user_id) receipt;
CREATE TEMP TABLE fixture_0134_member AS SELECT receipt.* FROM fixture_0134_context c,
  fixture_0134_invitation invitation,
  LATERAL app_private.accept_organization_directed_account_invitation_v1(c.app_user_id, invitation.invitation_id) receipt;
CREATE TEMP TABLE fixture_0134_project_member AS SELECT receipt.* FROM fixture_0134_owner owner,
  fixture_0134_org org, fixture_0134_member member,
  LATERAL app_private.assign_organization_project_member_v1(owner.app_user_id,
    '00000000-0134-4000-8000-000000000001', org.organization_workspace_id,
    '00000000-0134-2000-8000-000000000001', member.organization_membership_id) receipt;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id, question_id, position, prompt,
  question_type, is_required, allow_unknown, allow_refused, allow_not_applicable, maximum_length)
SELECT questionnaire_version_id, '0134-private-answer', 1, '0134 private question', 'long_text',
  false, true, true, true, 2000 FROM fixture_0134_context;
CREATE TEMP TABLE fixture_0134_target AS SELECT target FROM fixture_0134_context c,
  LATERAL app_data.create_promotion_target(c.app_user_id, c.workspace_id, c.project_id, 'person',
    '0134 private person', '+1 312 555 0134', 'private-0134@example.test', '0134-person') created;

CREATE FUNCTION pg_temp.submit_0134(contact text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; result record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT submitted.* INTO STRICT result FROM app_data.apply_contact_submit_v3(c.app_user_id, contact || '-submit',
    1, 'contact.submit.v1', '0134-device', contact, 0,
    jsonb_build_object('contactId', contact, 'workspaceId', c.workspace_id, 'projectId', c.project_id,
      'questionnaireVersionId', c.questionnaire_version_id, 'reason', '0134 private reason',
      'occurredAtUtc', '2025-03-09T07:59:59.123456Z', 'occurredTimeZone', 'America/Chicago',
      'channel', 'face_to_face', 'channelDetail', '0134 private detail',
      'location', jsonb_build_object('kind', 'pending_resolution', 'latitude', 41.7897,
        'longitude', -87.5997, 'accuracyMeters', 8.5), 'reachCount', 4, 'interestLevel', 3,
      'answers', jsonb_build_array(jsonb_build_object('questionId', '0134-private-answer', 'state', 'answered',
        'type', 'long_text', 'value', '0134 private answer 汉字')),
      'targetLinks', jsonb_build_array(jsonb_build_object('targetId', (SELECT target->>'target_id' FROM fixture_0134_target),
        'targetType', 'person', 'responseLevel', 4, 'followUpConsent', 'yes',
        'institutionRepresentativeConfirmed', false, 'confirmStageZero', true)))) submitted;
  PERFORM pg_temp.assert_0134(result.result_code = 'accepted', contact || ' submit was rejected');
END
$function$;
CREATE FUNCTION pg_temp.revise_0134(contact text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; revision integer; snapshot jsonb; result record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT current_revision INTO STRICT revision FROM app_data.contacts WHERE contact_id = contact;
  SELECT r.snapshot INTO STRICT snapshot FROM app_data.contact_revisions r
    WHERE r.contact_id = contact AND r.revision_number = revision;
  SELECT revised.* INTO STRICT result FROM app_data.apply_contact_revise_v3(c.app_user_id, contact || '-revise-' || revision,
    1, 'contact.revise.v1', '0134-device', contact, revision,
    snapshot || jsonb_build_object('reason', '0134 changed source', 'interestLevel', 1, 'reachCount', 6)) revised;
  PERFORM pg_temp.assert_0134(result.result_code = 'accepted', contact || ' revision was rejected');
END
$function$;
CREATE FUNCTION pg_temp.void_0134(contact text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; revision integer; result record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT current_revision INTO STRICT revision FROM app_data.contacts WHERE contact_id = contact;
  SELECT voided.* INTO STRICT result FROM app_data.apply_contact_void_v3(c.app_user_id, contact || '-void',
    1, 'contact.void.v1', '0134-device', contact, revision,
    jsonb_build_object('contactId', contact, 'workspaceId', c.workspace_id, 'projectId', c.project_id,
      'reason', '0134 void source')) voided;
  PERFORM pg_temp.assert_0134(result.result_code = 'accepted', contact || ' void was rejected');
END
$function$;
SELECT pg_temp.submit_0134('0134-' || kind) FROM unnest(ARRAY['rich', 'corrected', 'voided', 'expired', 'fault',
  'projection', 'zone-revision', 'zone-confirm']) kind;
CREATE TEMP TABLE fixture_0134_before AS SELECT pg_temp.legacy_state_0134() AS state;

SELECT pg_temp.expect_0134_failure('22023', 'invalid personal history contribution preview',
  'SELECT * FROM app_private.preview_personal_history_contribution_v1(NULL, NULL, NULL)');
SELECT pg_temp.expect_0134_failure('22023', 'invalid personal history contribution request',
  'SELECT * FROM app_private.confirm_personal_history_contribution_v1(NULL, NULL, NULL)');
DO $fixture$
DECLARE c record; owner record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT * INTO STRICT owner FROM fixture_0134_owner;
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      owner.app_user_id, '0134-rich', '00000000-0134-2000-8000-000000000001'));
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      owner.app_user_id, '0134-owner-source', '00000000-0134-2000-8000-000000000001'));
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '0134-rich', '00000000-0134-2000-8000-000000000002'));
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)', c.app_user_id, '0134-rich', c.project_id));
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,gen_random_uuid())', c.app_user_id, '0134-rich'));
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '0134-unknown', '00000000-0134-2000-8000-000000000001'));
END
$fixture$;
CREATE TEMP TABLE fixture_0134_preview AS SELECT receipt.* FROM fixture_0134_context c,
  LATERAL app_private.preview_personal_history_contribution_v1(c.app_user_id, '0134-rich',
    '00000000-0134-2000-8000-000000000001') receipt;
CREATE TEMP TABLE fixture_0134_second_preview AS SELECT receipt.* FROM fixture_0134_context c,
  LATERAL app_private.preview_personal_history_contribution_v1(c.app_user_id, '0134-rich',
    '00000000-0134-2000-8000-000000000001') receipt;
DO $fixture$
DECLARE c record; target_org uuid; preview uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT organization_workspace_id INTO STRICT target_org FROM fixture_0134_org;
  SELECT preview_id INTO STRICT preview FROM fixture_0134_preview;
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)',
      (SELECT app_user_id FROM fixture_0134_owner), preview));
  UPDATE app_data.projects SET status = 'archived' WHERE project_id = '00000000-0134-2000-8000-000000000001';
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '0134-rich', '00000000-0134-2000-8000-000000000001'));
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)', c.app_user_id, preview));
  UPDATE app_data.projects SET status = 'active' WHERE project_id = '00000000-0134-2000-8000-000000000001';
  UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = target_org;
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)', c.app_user_id, preview));
  UPDATE app_data.workspaces SET deleted_at = NULL WHERE workspace_id = target_org;
  UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = c.workspace_id;
  PERFORM pg_temp.expect_0134_failure('42501', 'personal history contribution forbidden',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '0134-rich', '00000000-0134-2000-8000-000000000001'));
  UPDATE app_data.workspaces SET deleted_at = NULL WHERE workspace_id = c.workspace_id;
END
$fixture$;
SELECT pg_temp.assert_0134((SELECT count(*) = 1 AND bool_and(
  contribution_preview_contract_id = 'personal-history-contribution-preview:v1' AND preview_id IS NOT NULL
  AND source_revision_number = 1 AND target_project_id = '00000000-0134-2000-8000-000000000001'
  AND isfinite(issued_at_utc) AND expires_at_utc = issued_at_utc + interval '15 minutes'
  AND occurred_at_utc = '2025-03-09T07:59:59.123456Z'::timestamptz AND occurred_time_zone = 'America/Chicago'
  AND channel = 'face_to_face' AND reach_count = 4 AND interest_level = 3) FROM fixture_0134_preview)
  AND (SELECT first.preview_id <> second.preview_id FROM fixture_0134_preview first CROSS JOIN fixture_0134_second_preview second)
  AND (SELECT array_agg(key ORDER BY key) = ARRAY['channel','contribution_preview_contract_id','expires_at_utc',
    'interest_level','issued_at_utc','occurred_at_utc','occurred_time_zone','preview_id','reach_count',
    'source_revision_number','target_project_id'] FROM fixture_0134_preview p, LATERAL jsonb_object_keys(to_jsonb(p)) key),
  'preview receipt, 15 minutes, or field allowlist drifted');
CREATE TEMP TABLE fixture_0134_confirmed AS SELECT receipt.* FROM fixture_0134_context c,
  fixture_0134_preview p, LATERAL app_private.confirm_personal_history_contribution_v1(c.app_user_id,
    '00000000-0134-5000-8000-000000000001', p.preview_id) receipt;
CREATE TEMP TABLE fixture_0134_replay AS SELECT receipt.* FROM fixture_0134_context c,
  fixture_0134_preview p, LATERAL app_private.confirm_personal_history_contribution_v1(c.app_user_id,
    '00000000-0134-5000-8000-000000000001', p.preview_id) receipt;
CREATE TEMP TABLE fixture_0134_frozen AS SELECT to_jsonb(copy) AS value
FROM app_private.organization_historical_contact_copies_v1 copy JOIN fixture_0134_confirmed USING(copy_id);
SELECT pg_temp.assert_0134((SELECT count(*) = 1 AND bool_and(
    contribution_contract_id = 'personal-history-contribution-confirmation:v1' AND copy_id IS NOT NULL
    AND target_project_id = '00000000-0134-2000-8000-000000000001' AND isfinite(confirmed_at_utc)) FROM fixture_0134_confirmed)
  AND NOT EXISTS ((TABLE fixture_0134_confirmed EXCEPT TABLE fixture_0134_replay)
    UNION ALL (TABLE fixture_0134_replay EXCEPT TABLE fixture_0134_confirmed))
  AND (SELECT count(*) = 1 FROM app_private.personal_history_contribution_confirmations_v1
    WHERE request_id = '00000000-0134-5000-8000-000000000001')
  AND (SELECT count(*) = 1 AND bool_and(copy.occurred_at_utc = p.occurred_at_utc
    AND copy.occurred_time_zone = p.occurred_time_zone AND copy.channel = p.channel
    AND copy.reach_count = p.reach_count AND copy.interest_level = p.interest_level
    AND copy.confirmed_at_utc = receipt.confirmed_at_utc)
    FROM app_private.organization_historical_contact_copies_v1 copy JOIN fixture_0134_confirmed receipt USING(copy_id)
    CROSS JOIN fixture_0134_preview p)
  AND (SELECT array_agg(key ORDER BY key) = ARRAY['channel','confirmed_at_utc','copy_id','interest_level',
    'occurred_at_utc','occurred_time_zone','reach_count','target_project_id']
    FROM fixture_0134_frozen copy, LATERAL jsonb_object_keys(copy.value) key),
  'confirmation, exact replay, immutable copy values, or field allowlist drifted');
SELECT pg_temp.assert_0134((SELECT state = pg_temp.legacy_state_0134() FROM fixture_0134_before),
  'preview or confirmation changed old contacts, answers, targets, feed, outbox, or reports');
DO $fixture$
DECLARE c record; owner record; preview uuid; other_preview uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT * INTO STRICT owner FROM fixture_0134_owner;
  SELECT preview_id INTO STRICT preview FROM fixture_0134_preview;
  SELECT preview_id INTO STRICT other_preview FROM fixture_0134_second_preview;
  PERFORM pg_temp.expect_0134_failure('22023', 'personal history contribution idempotency conflict',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,%L,%L)',
      owner.app_user_id, '00000000-0134-5000-8000-000000000001', preview));
  PERFORM pg_temp.expect_0134_failure('22023', 'personal history contribution idempotency conflict',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '00000000-0134-5000-8000-000000000001', other_preview));
  PERFORM pg_temp.expect_0134_failure('22023', 'personal history contribution idempotency conflict',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)', c.app_user_id, other_preview));
END
$fixture$;

CREATE TEMP TABLE fixture_0134_stale AS SELECT kind, receipt.* FROM fixture_0134_context c,
  unnest(ARRAY['corrected','voided','expired','fault','projection','zone-confirm']) kind,
  LATERAL app_private.preview_personal_history_contribution_v1(c.app_user_id, '0134-' || kind,
    '00000000-0134-2000-8000-000000000001') receipt;
SELECT pg_temp.revise_0134('0134-corrected');
SELECT pg_temp.void_0134('0134-voided');
-- Only synthetic preview times move; production guards are enabled for every call.
SET LOCAL session_replication_role = replica;
UPDATE app_private.personal_history_contribution_previews_v1 SET issued_at_utc = boundary.at - interval '15 minutes',
  expires_at_utc = boundary.at FROM (SELECT clock_timestamp() - interval '1 second' AS at) boundary
WHERE preview_id IN (SELECT preview_id FROM fixture_0134_stale WHERE kind = 'expired'
  UNION ALL SELECT preview_id FROM fixture_0134_preview);
SET LOCAL session_replication_role = origin;
DO $fixture$
DECLARE c record; p record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  FOR p IN SELECT * FROM fixture_0134_stale WHERE kind IN ('corrected','voided','expired') LOOP
    PERFORM pg_temp.expect_0134_failure('22023', 'personal history contribution idempotency conflict',
      format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)', c.app_user_id, p.preview_id));
  END LOOP;
  UPDATE app_data.contacts SET interest_level = 0 WHERE contact_id = '0134-projection';
  PERFORM pg_temp.expect_0134_failure('55000', 'personal history contribution unavailable',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '0134-projection', '00000000-0134-2000-8000-000000000001'));
  PERFORM pg_temp.expect_0134_failure('55000', 'personal history contribution unavailable',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)',
      c.app_user_id, (SELECT preview_id FROM fixture_0134_stale WHERE kind = 'projection')));
  UPDATE app_data.contacts SET interest_level = 3 WHERE contact_id = '0134-projection';
END
$fixture$;

DO $fixture$
DECLARE c record; result record; private_zone text := '0134 private note outside the time zone catalog';
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT revised.* INTO STRICT result FROM app_data.apply_contact_revise_v3(c.app_user_id,
    '0134-zone-revision-revise', 1, 'contact.revise.v1', '0134-device', '0134-zone-revision', 1,
    (SELECT snapshot || jsonb_build_object('reason', '0134 old writer time zone', 'occurredTimeZone', private_zone)
      FROM app_data.contact_revisions WHERE contact_id = '0134-zone-revision' AND revision_number = 1)) revised;
  PERFORM pg_temp.assert_0134(result.result_code = 'accepted', 'old writer did not accept the noncatalog time zone');
  PERFORM pg_temp.expect_0134_failure('55000', 'personal history contribution unavailable',
    format('SELECT * FROM app_private.preview_personal_history_contribution_v1(%L,%L,%L)',
      c.app_user_id, '0134-zone-revision', '00000000-0134-2000-8000-000000000001'));
END
$fixture$;
-- Equal synthetic projection and snapshot text must still satisfy the time zone allowlist.
SET LOCAL session_replication_role = replica;
UPDATE app_data.contacts SET occurred_time_zone = '0134 private note outside the time zone catalog'
WHERE contact_id = '0134-zone-confirm';
UPDATE app_data.contact_revisions SET snapshot = jsonb_set(snapshot, '{occurredTimeZone}',
  to_jsonb('0134 private note outside the time zone catalog'::text))
WHERE contact_id = '0134-zone-confirm' AND revision_number = 1;
SET LOCAL session_replication_role = origin;
DO $fixture$
DECLARE c record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  PERFORM pg_temp.expect_0134_failure('55000', 'personal history contribution unavailable',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,gen_random_uuid(),%L)',
      c.app_user_id, (SELECT preview_id FROM fixture_0134_stale WHERE kind = 'zone-confirm')));
END
$fixture$;

SELECT pg_temp.revise_0134('0134-rich');
SELECT pg_temp.void_0134('0134-rich');
UPDATE fixture_0134_before SET state = pg_temp.legacy_state_0134();
CREATE TEMP TABLE fixture_0134_frozen_replay AS SELECT receipt.* FROM fixture_0134_context c,
  fixture_0134_preview p, LATERAL app_private.confirm_personal_history_contribution_v1(c.app_user_id,
    '00000000-0134-5000-8000-000000000001', p.preview_id) receipt;
SELECT pg_temp.assert_0134(NOT EXISTS ((TABLE fixture_0134_confirmed EXCEPT TABLE fixture_0134_frozen_replay)
    UNION ALL (TABLE fixture_0134_frozen_replay EXCEPT TABLE fixture_0134_confirmed))
  AND (SELECT value = to_jsonb(copy) FROM fixture_0134_frozen frozen CROSS JOIN
    app_private.organization_historical_contact_copies_v1 copy JOIN fixture_0134_confirmed USING(copy_id))
  AND (SELECT state = pg_temp.legacy_state_0134() FROM fixture_0134_before),
  'source revision or void changed a frozen copy or its exact replay');

CREATE FUNCTION pg_temp.fail_0134_write()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF current_setting('fixture.fail_0134_table', true) = TG_TABLE_NAME THEN
    RAISE EXCEPTION USING ERRCODE = 'P0134', MESSAGE = '0134 injected write failure';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0134_copy_failure BEFORE INSERT ON app_private.organization_historical_contact_copies_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0134_write();
CREATE TRIGGER fixture_0134_confirmation_failure BEFORE INSERT ON app_private.personal_history_contribution_confirmations_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0134_write();
DO $fixture$
DECLARE c record; preview uuid; table_name text;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  SELECT preview_id INTO STRICT preview FROM fixture_0134_stale WHERE kind = 'fault';
  FOREACH table_name IN ARRAY ARRAY['organization_historical_contact_copies_v1', 'personal_history_contribution_confirmations_v1'] LOOP
    PERFORM set_config('fixture.fail_0134_table', table_name, true);
    PERFORM pg_temp.expect_0134_failure('P0134', '0134 injected write failure',
      format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,%L,%L)',
        c.app_user_id, '00000000-0134-5000-8000-000000000005', preview));
  END LOOP;
  PERFORM set_config('fixture.fail_0134_table', '', true);
END
$fixture$;
SELECT receipt.* FROM fixture_0134_context c, fixture_0134_stale p,
  LATERAL app_private.confirm_personal_history_contribution_v1(c.app_user_id,
    '00000000-0134-5000-8000-000000000005', p.preview_id) receipt WHERE p.kind = 'fault';
SELECT pg_temp.assert_0134((SELECT state = pg_temp.legacy_state_0134() FROM fixture_0134_before),
  'failure injection or recovery changed old business facts');

DO $fixture$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['personal_history_contribution_previews_v1',
      'organization_historical_contact_copies_v1', 'personal_history_contribution_confirmations_v1'] LOOP
    PERFORM pg_temp.expect_0134_failure('55000', NULL, format('UPDATE app_private.%I SET target_project_id=target_project_id', table_name));
    PERFORM pg_temp.expect_0134_failure('55000', NULL, format('DELETE FROM app_private.%I', table_name));
  END LOOP;
END
$fixture$;
UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id = NULL, source_contact_id = NULL
WHERE preview_id = (SELECT preview_id FROM fixture_0134_stale WHERE kind = 'fault');
UPDATE app_private.personal_history_contribution_confirmations_v1 SET actor_app_user_id = NULL, source_contact_id = NULL
WHERE request_id = '00000000-0134-5000-8000-000000000005';
DO $fixture$
DECLARE c record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0134_context;
  PERFORM pg_temp.expect_0134_failure('55000', NULL,
    format('UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id=%L WHERE source_contact_id IS NULL', c.app_user_id));
  PERFORM pg_temp.expect_0134_failure('55000', NULL,
    'UPDATE app_private.personal_history_contribution_confirmations_v1 SET source_contact_id=''0134-fault'' WHERE request_id=''00000000-0134-5000-8000-000000000005''');
  PERFORM pg_temp.expect_0134_failure('22023', 'personal history contribution idempotency conflict',
    format('SELECT * FROM app_private.confirm_personal_history_contribution_v1(%L,%L,%L)', c.app_user_id,
      '00000000-0134-5000-8000-000000000005', (SELECT preview_id FROM fixture_0134_stale WHERE kind = 'fault')));
END
$fixture$;
SELECT pg_temp.assert_0134(NOT has_function_privilege('tongxingzhe_runtime',
    'app_private.preview_personal_history_contribution_v1(uuid,text,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('tongxingzhe_runtime', 'app_private.confirm_personal_history_contribution_v1(uuid,uuid,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'app_private.preview_personal_history_contribution_v1(uuid,text,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'app_private.confirm_personal_history_contribution_v1(uuid,uuid,uuid)', 'EXECUTE'),
  'preview or confirmation is executable by PUBLIC or runtime');
SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE table_name text; actual_state text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['personal_history_contribution_previews_v1',
      'organization_historical_contact_copies_v1', 'personal_history_contribution_confirmations_v1'] LOOP
    actual_state := NULL;
    BEGIN EXECUTE format('SELECT * FROM app_private.%I', table_name);
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
    END;
    IF actual_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '0134 runtime accessed %', table_name; END IF;
  END LOOP;
END
$fixture$;
RESET ROLE;
ROLLBACK;
