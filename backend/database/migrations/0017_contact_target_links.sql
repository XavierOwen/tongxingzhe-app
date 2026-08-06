-- 0017_contact_target_links.sql
--
-- 一次接触可以保持匿名，也可以在每个 revision 中关联零到多个当前分配对象。
-- 场次兴趣、对象反应、触达人数和后续联系同意是互不推导的事实。

CREATE TABLE app_data.promotion_target_project_relationships (
  promotion_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  current_stage integer NOT NULL CHECK (current_stage BETWEEN 0 AND 4),
  established_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  established_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (promotion_target_id, project_id)
);

CREATE TABLE app_data.contact_target_links (
  contact_id text NOT NULL
    REFERENCES app_data.contacts (contact_id) ON DELETE RESTRICT,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  promotion_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  response_level integer CHECK (response_level BETWEEN 0 AND 4),
  follow_up_consent text NOT NULL CHECK (
    follow_up_consent IN (
      'yes', 'no', 'unknown', 'refused', 'not_applicable'
    )
  ),
  institution_representative_confirmed boolean NOT NULL,
  confirmed_project_entry boolean NOT NULL,
  PRIMARY KEY (contact_id, revision_number, promotion_target_id),
  FOREIGN KEY (contact_id, revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number)
    ON DELETE RESTRICT
);

CREATE INDEX contact_target_links_target_revision
  ON app_data.contact_target_links (
    promotion_target_id,
    contact_id,
    revision_number DESC
  );

REVOKE ALL PRIVILEGES
  ON app_data.promotion_target_project_relationships,
     app_data.contact_target_links
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.contact_target_link_error(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  target_links jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  link jsonb;
  target_id_text text;
  target_id_value uuid;
  target_row app_data.promotion_targets%ROWTYPE;
  seen_target_ids uuid[] := ARRAY[]::uuid[];
  response_text text;
  response_value integer;
BEGIN
  IF jsonb_typeof(target_links) <> 'array' THEN
    RETURN 'invalid_target_links';
  END IF;
  FOR link IN SELECT value FROM jsonb_array_elements(target_links)
  LOOP
    IF jsonb_typeof(link) <> 'object' THEN
      RETURN 'invalid_target_link';
    END IF;
    target_id_text := link->>'targetId';
    IF target_id_text IS NULL OR target_id_text !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    THEN
      RETURN 'invalid_target_id';
    END IF;
    target_id_value := target_id_text::uuid;
    IF target_id_value = ANY(seen_target_ids) THEN
      RETURN 'duplicate_contact_target';
    END IF;
    seen_target_ids := array_append(seen_target_ids, target_id_value);

    IF link->>'targetType' NOT IN ('person', 'institution')
      OR link->>'followUpConsent' NOT IN (
        'yes', 'no', 'unknown', 'refused', 'not_applicable'
      )
      OR jsonb_typeof(link->'institutionRepresentativeConfirmed') <>
        'boolean'
      OR jsonb_typeof(link->'confirmStageZero') <> 'boolean'
    THEN
      RETURN 'invalid_target_link';
    END IF;
    IF link->'responseLevel' IS NOT NULL
      AND jsonb_typeof(link->'responseLevel') <> 'null'
    THEN
      response_text := link->>'responseLevel';
      IF response_text !~ '^[0-4]$' THEN
        RETURN 'invalid_target_response_level';
      END IF;
      response_value := response_text::integer;
    ELSE
      response_value := NULL;
    END IF;

    SELECT * INTO target_row
    FROM app_data.promotion_targets AS candidate
    WHERE candidate.promotion_target_id = target_id_value
      AND candidate.workspace_id = trusted_workspace_id
      AND candidate.status = 'active';
    IF NOT FOUND OR NOT EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS assignment_row
      WHERE assignment_row.promotion_target_id = target_id_value
        AND assignment_row.app_user_id = trusted_app_user_id
        AND assignment_row.ended_at IS NULL
    ) THEN
      RETURN 'target_forbidden';
    END IF;
    IF target_row.target_type <> link->>'targetType' THEN
      RETURN 'target_type_mismatch';
    END IF;
    IF target_row.target_type = 'person'
      AND (link->>'institutionRepresentativeConfirmed')::boolean
    THEN
      RETURN 'person_representative_confirmation_forbidden';
    END IF;
    IF target_row.target_type = 'institution'
      AND response_value IS NOT NULL
      AND NOT (link->>'institutionRepresentativeConfirmed')::boolean
    THEN
      RETURN 'institution_response_requires_representative';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM app_data.promotion_target_project_relationships AS relation_row
      WHERE relation_row.promotion_target_id = target_id_value
        AND relation_row.project_id = trusted_project_id
    ) AND NOT (link->>'confirmStageZero')::boolean THEN
      RETURN 'target_project_confirmation_required';
    END IF;
  END LOOP;
  RETURN NULL;
END
$function$;

CREATE FUNCTION app_data.install_contact_target_links(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  target_contact_id text,
  target_revision_number integer,
  target_links jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_error text;
BEGIN
  validation_error := app_data.contact_target_link_error(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    target_links
  );
  IF validation_error IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = validation_error;
  END IF;

  INSERT INTO app_data.promotion_target_project_relationships (
    promotion_target_id,
    project_id,
    current_stage,
    established_by_app_user_id
  )
  SELECT
    (link->>'targetId')::uuid,
    trusted_project_id,
    0,
    trusted_app_user_id
  FROM jsonb_array_elements(target_links) AS links(link)
  WHERE (link->>'confirmStageZero')::boolean
  ON CONFLICT (promotion_target_id, project_id) DO NOTHING;

  INSERT INTO app_data.contact_target_links (
    contact_id,
    revision_number,
    promotion_target_id,
    response_level,
    follow_up_consent,
    institution_representative_confirmed,
    confirmed_project_entry
  )
  SELECT
    target_contact_id,
    target_revision_number,
    (link->>'targetId')::uuid,
    (link->>'responseLevel')::integer,
    link->>'followUpConsent',
    (link->>'institutionRepresentativeConfirmed')::boolean,
    (link->>'confirmStageZero')::boolean
  FROM jsonb_array_elements(target_links) AS links(link);
END
$function$;

CREATE FUNCTION app_data.replay_processed_contact_target_command(
  trusted_app_user_id uuid,
  client_command_id text
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF trusted_app_user_id IS NULL OR client_command_id IS NULL THEN
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      trusted_app_user_id::text || ':' || client_command_id,
      0
    )
  );
  RETURN QUERY
  SELECT
    CASE
      WHEN processed.result_code = 'accepted' THEN 'duplicate'
      ELSE processed.result_code
    END,
    processed.server_cursor::text,
    processed.failure_code
  FROM app_data.processed_commands AS processed
  WHERE processed.app_user_id = trusted_app_user_id
    AND processed.command_id = client_command_id;
END
$function$;

CREATE FUNCTION app_data.finalize_contact_target_warehouse(
  target_contact_id text,
  target_revision_number integer
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  UPDATE app_data.warehouse_outbox AS warehouse
  SET analytics_payload =
    warehouse.analytics_payload - 'targetLinks' - 'target_links'
    || jsonb_build_object(
      'target_link_facts',
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'target_type', target.target_type,
              'response_level', link.response_level,
              'follow_up_consent', link.follow_up_consent
            )
            ORDER BY link.promotion_target_id
          )
          FROM app_data.contact_target_links AS link
          JOIN app_data.promotion_targets AS target
            ON target.promotion_target_id = link.promotion_target_id
          WHERE link.contact_id = target_contact_id
            AND link.revision_number = target_revision_number
        ),
        '[]'::jsonb
      )
    )
  WHERE warehouse.contact_id = target_contact_id
    AND warehouse.revision_number = target_revision_number;
$function$;

CREATE OR REPLACE FUNCTION app_data.contact_revision_comparison_value(
  snapshot jsonb,
  field_name text
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
  SELECT CASE field_name
    WHEN 'occurredAt' THEN jsonb_build_array(
      snapshot->'occurredAtUtc', snapshot->'occurredTimeZone'
    )
    WHEN 'channel' THEN jsonb_build_array(
      snapshot->'channel', snapshot->'channelDetail'
    )
    WHEN 'location' THEN snapshot->'location'
    WHEN 'reachCount' THEN snapshot->'reachCount'
    WHEN 'interestLevel' THEN snapshot->'interestLevel'
    WHEN 'answers' THEN COALESCE(
      (
        SELECT jsonb_object_agg(
          answer->>'questionId',
          answer - 'questionId'
          ORDER BY answer->>'questionId'
        )
        FROM jsonb_array_elements(
          COALESCE(
            snapshot->'_questionnaireAnswersV2',
            snapshot->'answers',
            '[]'::jsonb
          )
        ) AS answer_row(answer)
      ),
      '{}'::jsonb
    )
    WHEN 'targetLinks' THEN COALESCE(
      (
        SELECT jsonb_object_agg(
          link->>'targetId',
          link - 'targetId'
          ORDER BY link->>'targetId'
        )
        FROM jsonb_array_elements(
          COALESCE(snapshot->'targetLinks', '[]'::jsonb)
        ) AS link_row(link)
      ),
      '{}'::jsonb
    )
    ELSE 'null'::jsonb
  END;
$function$;

CREATE OR REPLACE FUNCTION app_data.contact_revision_changed_fields(
  base_snapshot jsonb,
  candidate_snapshot jsonb
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
  SELECT COALESCE(array_agg(field_name ORDER BY ordinal), ARRAY[]::text[])
  FROM unnest(ARRAY[
    'occurredAt',
    'channel',
    'location',
    'reachCount',
    'interestLevel',
    'answers',
    'targetLinks'
  ]) WITH ORDINALITY AS field_row(field_name, ordinal)
  WHERE app_data.contact_revision_comparison_value(
      base_snapshot,
      field_name
    ) IS DISTINCT FROM app_data.contact_revision_comparison_value(
      candidate_snapshot,
      field_name
    );
$function$;

CREATE OR REPLACE FUNCTION app_data.merge_contact_revision_snapshots(
  current_snapshot jsonb,
  proposed_snapshot jsonb,
  proposed_changed_fields text[]
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  merged_snapshot jsonb := current_snapshot;
  merged_answers jsonb;
BEGIN
  IF 'occurredAt' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'occurredAtUtc', proposed_snapshot->'occurredAtUtc',
      'occurredTimeZone', proposed_snapshot->'occurredTimeZone'
    );
  END IF;
  IF 'channel' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'channel', proposed_snapshot->'channel',
      'channelDetail', proposed_snapshot->'channelDetail'
    );
  END IF;
  IF 'location' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'location', proposed_snapshot->'location'
    );
  END IF;
  IF 'reachCount' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'reachCount', proposed_snapshot->'reachCount'
    );
  END IF;
  IF 'interestLevel' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'interestLevel', proposed_snapshot->'interestLevel'
    );
  END IF;
  IF 'answers' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'answers', proposed_snapshot->'answers'
    );
  END IF;
  IF 'targetLinks' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'targetLinks', proposed_snapshot->'targetLinks'
    );
  END IF;
  IF proposed_snapshot ? '_questionnaireAnswersV2' THEN
    merged_answers := COALESCE(
      current_snapshot->'_questionnaireAnswersV2',
      current_snapshot->'answers',
      '[]'::jsonb
    );
    IF 'answers' = ANY(proposed_changed_fields) THEN
      merged_answers := proposed_snapshot->'_questionnaireAnswersV2';
    END IF;
    merged_snapshot := jsonb_set(
      merged_snapshot - '_questionnaireAnswersV2',
      '{answers}',
      '[]'::jsonb
    ) || jsonb_build_object('_questionnaireAnswersV2', merged_answers);
  END IF;
  RETURN merged_snapshot;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.read_contact_revision_conflict(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  client_command_id text
)
RETURNS TABLE (conflict_payload jsonb)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'conflictId', conflict_row.conflict_id,
    'contactId', conflict_row.contact_id,
    'baseRevision', conflict_row.base_revision,
    'currentRevision', conflict_row.current_revision,
    'conflictingFields', to_jsonb(conflict_row.conflicting_fields),
    'questionnaireVersionId',
      conflict_row.current_snapshot->'questionnaireVersionId',
    'currentRevisionKind', conflict_row.current_snapshot->'revisionKind',
    'currentRevisedAtUtc', conflict_row.current_snapshot->'revisedAtUtc',
    'currentReason', conflict_row.current_snapshot->'reason',
    'currentSnapshot', jsonb_build_object(
      'occurredAtUtc', conflict_row.current_snapshot->'occurredAtUtc',
      'occurredTimeZone', conflict_row.current_snapshot->'occurredTimeZone',
      'channel', conflict_row.current_snapshot->'channel',
      'channelDetail', conflict_row.current_snapshot->'channelDetail',
      'location', conflict_row.current_snapshot->'location',
      'reachCount', conflict_row.current_snapshot->'reachCount',
      'interestLevel', conflict_row.current_snapshot->'interestLevel',
      'answers', conflict_row.current_snapshot->'answers',
      'targetLinks', COALESCE(
        conflict_row.current_snapshot->'targetLinks', '[]'::jsonb
      )
    ),
    'proposedSnapshot', jsonb_build_object(
      'occurredAtUtc', conflict_row.proposed_snapshot->'occurredAtUtc',
      'occurredTimeZone', conflict_row.proposed_snapshot->'occurredTimeZone',
      'channel', conflict_row.proposed_snapshot->'channel',
      'channelDetail', conflict_row.proposed_snapshot->'channelDetail',
      'location', conflict_row.proposed_snapshot->'location',
      'reachCount', conflict_row.proposed_snapshot->'reachCount',
      'interestLevel', conflict_row.proposed_snapshot->'interestLevel',
      'answers', conflict_row.proposed_snapshot->'answers',
      'targetLinks', COALESCE(
        conflict_row.proposed_snapshot->'targetLinks', '[]'::jsonb
      )
    )
  )
  FROM app_data.contact_revision_conflicts AS conflict_row
  WHERE conflict_row.app_user_id = trusted_app_user_id
    AND conflict_row.workspace_id = trusted_workspace_id
    AND conflict_row.project_id = trusted_project_id
    AND conflict_row.command_id = client_command_id;
$function$;

CREATE FUNCTION app_data.apply_contact_submit_v3(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_error text;
  inner_result record;
  prior_result record;
BEGIN
  SELECT * INTO prior_result
  FROM app_data.replay_processed_contact_target_command(
    trusted_app_user_id, client_command_id
  );
  IF FOUND THEN
    RETURN QUERY SELECT prior_result.result_code::text,
      prior_result.server_cursor::text, prior_result.failure_code::text;
    RETURN;
  END IF;
  validation_error := app_data.contact_target_link_error(
    trusted_app_user_id,
    (typed_payload->>'workspaceId')::uuid,
    (typed_payload->>'projectId')::uuid,
    COALESCE(typed_payload->'targetLinks', '[]'::jsonb)
  );
  IF validation_error IS NOT NULL THEN
    RETURN QUERY SELECT 'rejected', NULL::text, validation_error;
    RETURN;
  END IF;
  SELECT * INTO inner_result FROM app_data.apply_contact_submit_v2(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision, typed_payload
  );
  IF inner_result.result_code = 'accepted' THEN
    PERFORM app_data.install_contact_target_links(
      trusted_app_user_id,
      (typed_payload->>'workspaceId')::uuid,
      (typed_payload->>'projectId')::uuid,
      client_aggregate_id,
      1,
      COALESCE(typed_payload->'targetLinks', '[]'::jsonb)
    );
    PERFORM app_data.finalize_contact_target_warehouse(
      client_aggregate_id,
      1
    );
  END IF;
  RETURN QUERY SELECT inner_result.result_code::text,
    inner_result.server_cursor::text, inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_contact_revise_v3(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_error text;
  inner_result record;
  prior_result record;
  accepted_revision integer;
  accepted_links jsonb;
BEGIN
  SELECT * INTO prior_result
  FROM app_data.replay_processed_contact_target_command(
    trusted_app_user_id, client_command_id
  );
  IF FOUND THEN
    RETURN QUERY SELECT prior_result.result_code::text,
      prior_result.server_cursor::text, prior_result.failure_code::text;
    RETURN;
  END IF;
  validation_error := app_data.contact_target_link_error(
    trusted_app_user_id,
    (typed_payload->>'workspaceId')::uuid,
    (typed_payload->>'projectId')::uuid,
    COALESCE(typed_payload->'targetLinks', '[]'::jsonb)
  );
  IF validation_error IS NOT NULL THEN
    RETURN QUERY SELECT 'rejected', NULL::text, validation_error;
    RETURN;
  END IF;
  SELECT * INTO inner_result FROM app_data.apply_contact_revise_v2(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision, typed_payload
  );
  IF inner_result.result_code = 'accepted' THEN
    SELECT feed.revision_number,
           COALESCE(revision_row.snapshot->'targetLinks', '[]'::jsonb)
      INTO accepted_revision, accepted_links
    FROM app_data.change_feed AS feed
    JOIN app_data.contact_revisions AS revision_row
      ON revision_row.contact_id = feed.aggregate_id
     AND revision_row.revision_number = feed.revision_number
    WHERE feed.cursor_token = inner_result.server_cursor::uuid;
    PERFORM app_data.install_contact_target_links(
      trusted_app_user_id,
      (typed_payload->>'workspaceId')::uuid,
      (typed_payload->>'projectId')::uuid,
      client_aggregate_id,
      accepted_revision,
      accepted_links
    );
    PERFORM app_data.finalize_contact_target_warehouse(
      client_aggregate_id,
      accepted_revision
    );
  END IF;
  RETURN QUERY SELECT inner_result.result_code::text,
    inner_result.server_cursor::text, inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_contact_conflict_resolution_v3(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_error text;
  inner_result record;
  prior_result record;
  accepted_revision integer;
  accepted_links jsonb;
BEGIN
  SELECT * INTO prior_result
  FROM app_data.replay_processed_contact_target_command(
    trusted_app_user_id, client_command_id
  );
  IF FOUND THEN
    RETURN QUERY SELECT prior_result.result_code::text,
      prior_result.server_cursor::text, prior_result.failure_code::text;
    RETURN;
  END IF;
  validation_error := app_data.contact_target_link_error(
    trusted_app_user_id,
    (typed_payload->>'workspaceId')::uuid,
    (typed_payload->>'projectId')::uuid,
    COALESCE(typed_payload->'targetLinks', '[]'::jsonb)
  );
  IF validation_error IS NOT NULL THEN
    RETURN QUERY SELECT 'rejected', NULL::text, validation_error;
    RETURN;
  END IF;
  SELECT * INTO inner_result
  FROM app_data.apply_contact_conflict_resolution_v2(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision, typed_payload
  );
  IF inner_result.result_code = 'accepted' THEN
    SELECT feed.revision_number,
           COALESCE(revision_row.snapshot->'targetLinks', '[]'::jsonb)
      INTO accepted_revision, accepted_links
    FROM app_data.change_feed AS feed
    JOIN app_data.contact_revisions AS revision_row
      ON revision_row.contact_id = feed.aggregate_id
     AND revision_row.revision_number = feed.revision_number
    WHERE feed.cursor_token = inner_result.server_cursor::uuid;
    PERFORM app_data.install_contact_target_links(
      trusted_app_user_id,
      (typed_payload->>'workspaceId')::uuid,
      (typed_payload->>'projectId')::uuid,
      client_aggregate_id,
      accepted_revision,
      accepted_links
    );
    PERFORM app_data.finalize_contact_target_warehouse(
      client_aggregate_id,
      accepted_revision
    );
  END IF;
  RETURN QUERY SELECT inner_result.result_code::text,
    inner_result.server_cursor::text, inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_contact_void_v3(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  inner_result record;
  prior_result record;
  accepted_revision integer;
BEGIN
  SELECT * INTO prior_result
  FROM app_data.replay_processed_contact_target_command(
    trusted_app_user_id, client_command_id
  );
  IF FOUND THEN
    RETURN QUERY SELECT prior_result.result_code::text,
      prior_result.server_cursor::text, prior_result.failure_code::text;
    RETURN;
  END IF;
  SELECT * INTO inner_result FROM app_data.apply_contact_void_v2(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision, typed_payload
  );
  IF inner_result.result_code = 'accepted' THEN
    SELECT feed.revision_number INTO accepted_revision
    FROM app_data.change_feed AS feed
    WHERE feed.cursor_token = inner_result.server_cursor::uuid;
    INSERT INTO app_data.contact_target_links (
      contact_id, revision_number, promotion_target_id, response_level,
      follow_up_consent, institution_representative_confirmed,
      confirmed_project_entry
    )
    SELECT
      link.contact_id, accepted_revision, link.promotion_target_id,
      link.response_level, link.follow_up_consent,
      link.institution_representative_confirmed,
      link.confirmed_project_entry
    FROM app_data.contact_target_links AS link
    WHERE link.contact_id = client_aggregate_id
      AND link.revision_number = client_base_revision;
    PERFORM app_data.finalize_contact_target_warehouse(
      client_aggregate_id,
      accepted_revision
    );
  END IF;
  RETURN QUERY SELECT inner_result.result_code::text,
    inner_result.server_cursor::text, inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_draft_upsert_v3(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_error text;
  prior_result record;
BEGIN
  SELECT * INTO prior_result
  FROM app_data.replay_processed_contact_target_command(
    trusted_app_user_id, client_command_id
  );
  IF FOUND THEN
    RETURN QUERY SELECT prior_result.result_code::text,
      prior_result.server_cursor::text, prior_result.failure_code::text;
    RETURN;
  END IF;
  validation_error := app_data.contact_target_link_error(
    trusted_app_user_id,
    (typed_payload->>'workspaceId')::uuid,
    (typed_payload->>'projectId')::uuid,
    COALESCE(typed_payload->'targetLinks', '[]'::jsonb)
  );
  IF validation_error IS NOT NULL THEN
    RETURN QUERY SELECT 'rejected', NULL::text, validation_error;
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM app_data.apply_draft_upsert_v2(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision, typed_payload
  );
END
$function$;

CREATE OR REPLACE FUNCTION app_data.list_assigned_promotion_targets(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (target jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target access is forbidden';
  END IF;
  INSERT INTO app_data.promotion_target_access_events (
    workspace_id, promotion_target_id, actor_app_user_id, action
  )
  SELECT
    trusted_workspace_id,
    target_row.promotion_target_id,
    trusted_app_user_id,
    'viewed'
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active';
  RETURN QUERY
  SELECT app_data.promotion_target_document(target_row.promotion_target_id)
    || jsonb_build_object(
      'has_current_project_relationship',
      EXISTS (
        SELECT 1
        FROM app_data.promotion_target_project_relationships AS relation_row
        WHERE relation_row.promotion_target_id =
          target_row.promotion_target_id
          AND relation_row.project_id = trusted_project_id
      )
    )
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active'
  ORDER BY target_row.created_at DESC, target_row.promotion_target_id;
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.contact_target_link_error(uuid, uuid, uuid, jsonb),
  app_data.install_contact_target_links(
    uuid, uuid, uuid, text, integer, jsonb
  ),
  app_data.replay_processed_contact_target_command(uuid, text),
  app_data.finalize_contact_target_warehouse(text, integer),
  app_data.apply_contact_submit_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_revise_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_conflict_resolution_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_void_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_draft_upsert_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.apply_contact_submit_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_revise_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_conflict_resolution_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_void_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_draft_upsert_v3(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.contact_target_links IS
  'Append-only per-revision target facts; no target PII is duplicated here.';
COMMENT ON TABLE app_data.promotion_target_project_relationships IS
  'Explicit target entry into one project; Slice 4B creates stage 0 only.';
