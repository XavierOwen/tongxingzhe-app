-- This completes only the contribution-source unlink step, not account deletion.
CREATE TABLE app_private.account_history_contribution_unlink_completions_v1 (
  deletion_request_id uuid PRIMARY KEY,
  unlinked_at_utc timestamptz NOT NULL CHECK (isfinite(unlinked_at_utc))
);

REVOKE ALL ON TABLE app_private.account_history_contribution_unlink_completions_v1
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER account_history_contribution_unlink_completions_immutable
BEFORE UPDATE OR DELETE ON app_private.account_history_contribution_unlink_completions_v1
FOR EACH ROW EXECUTE FUNCTION app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_private.unlink_due_account_history_contributions_v1(
  trusted_app_user_id uuid,
  expected_deletion_request_id uuid
)
RETURNS TABLE (
  account_history_contribution_unlink_contract_id text,
  deletion_request_id uuid,
  unlinked_at_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  pass integer;
  actor_status text;
  preview_ids uuid[];
  confirmation_ids uuid[];
  organization_ids uuid[];
  locked_confirmation_ids uuid[];
  locked_organization_ids uuid[];
  selected_id uuid;
  reference_time timestamptz;
  current_cycle app_private.account_deletion_current%ROWTYPE;
  request_claim app_private.account_deletion_request_claims%ROWTYPE;
  completion app_private.account_history_contribution_unlink_completions_v1%ROWTYPE;
BEGIN
  IF expected_deletion_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid account history contribution unlink request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'account history contribution unlink requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account history contribution unlink forbidden';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'account-history-contribution-unlink:' || expected_deletion_request_id::text, 0
  ));

  FOR pass IN 1..2 LOOP
    WITH attributed_previews AS (
      SELECT preview.preview_id
      FROM app_private.personal_history_contribution_previews_v1 AS preview
      LEFT JOIN app_data.contacts AS source ON source.contact_id = preview.source_contact_id
      LEFT JOIN app_data.workspaces AS workspace ON workspace.workspace_id = source.workspace_id
      WHERE preview.actor_app_user_id = trusted_app_user_id OR source.app_user_id = trusted_app_user_id
        OR workspace.personal_owner_app_user_id = trusted_app_user_id
    ), attributed_confirmations AS (
      SELECT claim.preview_id
      FROM app_private.personal_history_contribution_confirmations_v1 AS claim
      LEFT JOIN app_data.contacts AS source ON source.contact_id = claim.source_contact_id
      LEFT JOIN app_data.workspaces AS workspace ON workspace.workspace_id = source.workspace_id
      WHERE claim.actor_app_user_id = trusted_app_user_id OR source.app_user_id = trusted_app_user_id
        OR workspace.personal_owner_app_user_id = trusted_app_user_id
    ), selected_previews AS (
      SELECT preview_id FROM attributed_previews UNION SELECT preview_id FROM attributed_confirmations
    ), selected_confirmations AS (
      SELECT claim.request_id, claim.target_project_id
      FROM app_private.personal_history_contribution_confirmations_v1 AS claim
      WHERE claim.preview_id IN (SELECT selected.preview_id FROM selected_previews AS selected)
    ), selected_projects AS (
      SELECT preview.target_project_id FROM app_private.personal_history_contribution_previews_v1 AS preview
      WHERE preview.preview_id IN (SELECT selected.preview_id FROM selected_previews AS selected)
      UNION SELECT target_project_id FROM selected_confirmations
    )
    SELECT ARRAY(SELECT selected.preview_id FROM selected_previews AS selected ORDER BY selected.preview_id),
      ARRAY(SELECT selected.request_id FROM selected_confirmations AS selected ORDER BY selected.request_id),
      ARRAY(SELECT DISTINCT project.workspace_id FROM app_data.projects AS project
        WHERE project.project_id IN (SELECT target_project_id FROM selected_projects) ORDER BY project.workspace_id)
    INTO preview_ids, confirmation_ids, organization_ids;

    IF pass = 1 THEN
      locked_confirmation_ids := confirmation_ids;
      locked_organization_ids := organization_ids;
      FOREACH selected_id IN ARRAY locked_confirmation_ids LOOP
        PERFORM pg_advisory_xact_lock(hashtextextended(
          'personal-history-contribution-confirmation:' || selected_id::text, 0
        ));
      END LOOP;
      -- Keep the source writer's author FK checks compatible with this status fence.
      SELECT actor.status INTO actor_status FROM app_data.app_users AS actor
      WHERE actor.app_user_id = trusted_app_user_id FOR NO KEY UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account history contribution unlink forbidden';
      END IF;
      FOREACH selected_id IN ARRAY locked_organization_ids LOOP
        PERFORM app_private.lock_organization_governance_v1(selected_id);
      END LOOP;
    ELSIF NOT (confirmation_ids <@ locked_confirmation_ids AND organization_ids <@ locked_organization_ids) THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account history contribution unlink retry required';
    END IF;
  END LOOP;

  reference_time := clock_timestamp();
  SELECT cycle.* INTO current_cycle FROM app_private.account_deletion_current AS cycle
  WHERE cycle.app_user_id = trusted_app_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account history contribution unlink unavailable';
  END IF;
  IF current_cycle.deletion_request_id IS DISTINCT FROM expected_deletion_request_id THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account history contribution unlink cycle conflict';
  END IF;
  SELECT claim.* INTO request_claim FROM app_private.account_deletion_request_claims AS claim
  WHERE claim.request_id = current_cycle.deletion_request_id;
  IF NOT FOUND OR actor_status IS DISTINCT FROM 'deletion_pending'
    OR current_cycle.status IS DISTINCT FROM 'deletion_pending'
    OR current_cycle.restored_at_utc IS NOT NULL
    OR request_claim.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
    OR request_claim.deletion_request_id IS DISTINCT FROM current_cycle.deletion_request_id
    OR request_claim.effective_at_utc IS DISTINCT FROM current_cycle.effective_at_utc
    OR request_claim.purge_after_utc IS DISTINCT FROM current_cycle.purge_after_utc
    OR NOT isfinite(current_cycle.effective_at_utc) OR NOT isfinite(current_cycle.purge_after_utc)
    OR current_cycle.purge_after_utc <> current_cycle.effective_at_utc + interval '720 hours'
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account history contribution unlink unavailable';
  END IF;
  IF reference_time < current_cycle.purge_after_utc THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account history contribution unlink not due';
  END IF;

  IF EXISTS (
    SELECT 1 FROM (
      SELECT preview.actor_app_user_id, preview.source_contact_id, preview.target_project_id
      FROM app_private.personal_history_contribution_previews_v1 AS preview WHERE preview.preview_id = ANY(preview_ids)
      UNION ALL
      SELECT claim.actor_app_user_id, claim.source_contact_id, claim.target_project_id
      FROM app_private.personal_history_contribution_confirmations_v1 AS claim WHERE claim.request_id = ANY(confirmation_ids)
    ) AS lineage
    LEFT JOIN app_data.contacts AS source ON source.contact_id = lineage.source_contact_id
    LEFT JOIN app_data.workspaces AS source_workspace ON source_workspace.workspace_id = source.workspace_id
    LEFT JOIN app_data.projects AS source_project ON source_project.project_id = source.project_id
    LEFT JOIN app_data.projects AS target_project ON target_project.project_id = lineage.target_project_id
    LEFT JOIN app_data.workspaces AS target_workspace ON target_workspace.workspace_id = target_project.workspace_id
    WHERE (lineage.actor_app_user_id IS NOT NULL AND lineage.actor_app_user_id IS DISTINCT FROM trusted_app_user_id)
      OR (lineage.source_contact_id IS NOT NULL AND (
        source.contact_id IS NULL OR source.app_user_id IS DISTINCT FROM trusted_app_user_id
        OR source_workspace.workspace_kind IS DISTINCT FROM 'personal'
        OR source_workspace.personal_owner_app_user_id IS DISTINCT FROM trusted_app_user_id
        OR source_project.workspace_id IS DISTINCT FROM source.workspace_id))
      OR target_workspace.workspace_kind IS DISTINCT FROM 'organization'
  ) OR EXISTS (
    SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 AS claim
    LEFT JOIN app_private.personal_history_contribution_previews_v1 AS preview USING (preview_id)
    LEFT JOIN app_private.organization_historical_contact_copies_v1 AS copy USING (copy_id)
    WHERE claim.request_id = ANY(confirmation_ids) AND (
      preview.preview_id IS NULL OR copy.copy_id IS NULL
      OR claim.target_project_id IS DISTINCT FROM preview.target_project_id
      OR claim.target_project_id IS DISTINCT FROM copy.target_project_id
      OR claim.confirmed_at_utc IS DISTINCT FROM copy.confirmed_at_utc
      OR (claim.actor_app_user_id IS NOT NULL AND preview.actor_app_user_id IS NOT NULL
        AND claim.actor_app_user_id IS DISTINCT FROM preview.actor_app_user_id)
      OR (claim.source_contact_id IS NOT NULL AND preview.source_contact_id IS NOT NULL
        AND claim.source_contact_id IS DISTINCT FROM preview.source_contact_id))
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account history contribution unlink unavailable';
  END IF;

  SELECT receipt.* INTO completion FROM app_private.account_history_contribution_unlink_completions_v1 AS receipt
  WHERE receipt.deletion_request_id = expected_deletion_request_id;
  IF FOUND THEN
    IF cardinality(preview_ids) <> 0 OR cardinality(confirmation_ids) <> 0
      OR completion.unlinked_at_utc < current_cycle.purge_after_utc OR completion.unlinked_at_utc > reference_time
    THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account history contribution unlink unavailable';
    END IF;
    RETURN QUERY SELECT 'account-history-contribution-unlink:v1'::text,
      completion.deletion_request_id, completion.unlinked_at_utc;
    RETURN;
  END IF;

  UPDATE app_private.personal_history_contribution_previews_v1 AS preview
  SET actor_app_user_id = NULL, source_contact_id = NULL
  WHERE preview.preview_id = ANY(preview_ids)
    AND (preview.actor_app_user_id IS NOT NULL OR preview.source_contact_id IS NOT NULL);
  UPDATE app_private.personal_history_contribution_confirmations_v1 AS claim
  SET actor_app_user_id = NULL, source_contact_id = NULL
  WHERE claim.request_id = ANY(confirmation_ids)
    AND (claim.actor_app_user_id IS NOT NULL OR claim.source_contact_id IS NOT NULL);
  INSERT INTO app_private.account_history_contribution_unlink_completions_v1(deletion_request_id, unlinked_at_utc)
  VALUES (expected_deletion_request_id, reference_time);
  RETURN QUERY SELECT 'account-history-contribution-unlink:v1'::text, expected_deletion_request_id, reference_time;
END
$function$;

REVOKE ALL ON FUNCTION app_private.unlink_due_account_history_contributions_v1(uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format('ALTER TABLE app_private.account_history_contribution_unlink_completions_v1 OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.unlink_due_account_history_contributions_v1(uuid,uuid) OWNER TO %I', trusted_owner);
END
$owner$;
