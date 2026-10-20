\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0134_purge_actor AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0134-purge.example','actor');
SELECT * FROM app_data.list_personal_project_contexts(
  'https://synthetic-0134-purge.example','actor');
DO $source$
DECLARE result record;
BEGIN
  SELECT submitted.* INTO result FROM fixture_0134_purge_actor actor
  CROSS JOIN LATERAL app_data.apply_contact_submit(
    actor.app_user_id,'0134-purge-submit',1,'contact.submit.v1','0134-device','0134-purge-source',0,
    jsonb_build_object('contactId','0134-purge-source','workspaceId',actor.workspace_id,
      'projectId',actor.project_id,'questionnaireVersionId',actor.questionnaire_version_id,
      'occurredAtUtc','2026-01-02T03:04:05Z','occurredTimeZone','Asia/Shanghai',
      'channel','voice_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',2,'interestLevel',3,'answers','[]'::jsonb)) submitted;
  IF result.result_code IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION '0134 purge source submission rejected';
  END IF;
END
$source$;

CREATE TEMP TABLE fixture_0134_purge_other_org AS
SELECT * FROM app_private.create_organization_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),gen_random_uuid(),'0134 preserved organization');
CREATE TEMP TABLE fixture_0134_purge_other_project AS
WITH created AS (
  INSERT INTO app_data.projects(workspace_id,display_name)
  SELECT organization_workspace_id,'0134 preserved project' FROM fixture_0134_purge_other_org
  RETURNING project_id
) SELECT * FROM created;
SELECT * FROM app_private.assign_organization_project_member_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),gen_random_uuid(),
  (SELECT organization_workspace_id FROM fixture_0134_purge_other_org),
  (SELECT project_id FROM fixture_0134_purge_other_project),
  (SELECT organization_membership_id FROM fixture_0134_purge_other_org));
CREATE TEMP TABLE fixture_0134_purge_other_preview AS
SELECT * FROM app_private.preview_personal_history_contribution_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),'0134-purge-source',
  (SELECT project_id FROM fixture_0134_purge_other_project));
CREATE TEMP TABLE fixture_0134_purge_other_copy AS
SELECT * FROM app_private.confirm_personal_history_contribution_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),gen_random_uuid(),
  (SELECT preview_id FROM fixture_0134_purge_other_preview));

CREATE TEMP TABLE fixture_0134_purge_preserved(relation_name text,row_data jsonb);
DO $snapshot$
DECLARE relation_name text;
BEGIN
  FOR relation_name IN SELECT format('%I.%I',namespace.nspname,relation.relname)
    FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
    WHERE namespace.nspname IN ('app_data','app_private') AND relation.relkind='r' LOOP
    EXECUTE format('INSERT INTO fixture_0134_purge_preserved SELECT %L,to_jsonb(t) FROM %s t',relation_name,relation_name);
  END LOOP;
END
$snapshot$;

CREATE TEMP TABLE fixture_0134_purge_org AS
SELECT * FROM app_private.create_organization_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),gen_random_uuid(),'0134 deleted organization');
CREATE TEMP TABLE fixture_0134_purge_project AS
WITH created AS (
  INSERT INTO app_data.projects(workspace_id,display_name)
  SELECT organization_workspace_id,'0134 deleted project' FROM fixture_0134_purge_org
  RETURNING project_id
) SELECT * FROM created;
SELECT * FROM app_private.assign_organization_project_member_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),gen_random_uuid(),
  (SELECT organization_workspace_id FROM fixture_0134_purge_org),
  (SELECT project_id FROM fixture_0134_purge_project),
  (SELECT organization_membership_id FROM fixture_0134_purge_org));
CREATE TEMP TABLE fixture_0134_purge_preview AS
SELECT * FROM app_private.preview_personal_history_contribution_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),'0134-purge-source',
  (SELECT project_id FROM fixture_0134_purge_project));
CREATE TEMP TABLE fixture_0134_purge_request AS SELECT gen_random_uuid() AS request_id;
CREATE TEMP TABLE fixture_0134_purge_copy AS
SELECT * FROM app_private.confirm_personal_history_contribution_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),(SELECT request_id FROM fixture_0134_purge_request),
  (SELECT preview_id FROM fixture_0134_purge_preview));
-- An unused preview belongs to the target organization as well.
SELECT * FROM app_private.preview_personal_history_contribution_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),'0134-purge-source',
  (SELECT project_id FROM fixture_0134_purge_project));

CREATE FUNCTION pg_temp.expect_0134_purge_failure(expected_state text,statement text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION '0134 purge expected SQLSTATE %, got % for %',expected_state,actual_state,statement;
  END IF;
END
$function$;

SAVEPOINT contribution_unlink;
UPDATE app_private.personal_history_contribution_previews_v1
SET actor_app_user_id=NULL,source_contact_id=NULL
WHERE preview_id=(SELECT preview_id FROM fixture_0134_purge_preview);
UPDATE app_private.personal_history_contribution_confirmations_v1
SET actor_app_user_id=NULL,source_contact_id=NULL
WHERE request_id=(SELECT request_id FROM fixture_0134_purge_request);
DO $unlinked$
BEGIN
  IF EXISTS (SELECT 1 FROM app_private.personal_history_contribution_previews_v1
      WHERE preview_id=(SELECT preview_id FROM fixture_0134_purge_preview)
        AND (actor_app_user_id IS NOT NULL OR source_contact_id IS NOT NULL))
    OR EXISTS (SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1
      WHERE request_id=(SELECT request_id FROM fixture_0134_purge_request)
        AND (actor_app_user_id IS NOT NULL OR source_contact_id IS NOT NULL)) THEN
    RAISE EXCEPTION '0134 contribution unlink failed';
  END IF;
END
$unlinked$;
SELECT pg_temp.expect_0134_purge_failure('55000',
  'UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id=(SELECT app_user_id FROM fixture_0134_purge_actor) WHERE preview_id=(SELECT preview_id FROM fixture_0134_purge_preview)');
SELECT pg_temp.expect_0134_purge_failure('55000',
  'UPDATE app_private.personal_history_contribution_previews_v1 SET source_contact_id=''0134-purge-source'' WHERE preview_id=(SELECT preview_id FROM fixture_0134_purge_preview)');
SELECT pg_temp.expect_0134_purge_failure('55000',
  'UPDATE app_private.personal_history_contribution_confirmations_v1 SET actor_app_user_id=(SELECT app_user_id FROM fixture_0134_purge_actor) WHERE request_id=(SELECT request_id FROM fixture_0134_purge_request)');
SELECT pg_temp.expect_0134_purge_failure('55000',
  'UPDATE app_private.personal_history_contribution_confirmations_v1 SET source_contact_id=''0134-purge-source'' WHERE request_id=(SELECT request_id FROM fixture_0134_purge_request)');
ROLLBACK TO contribution_unlink;

CREATE TEMP TABLE fixture_0134_purge_cycle AS
SELECT * FROM app_private.request_organization_deletion_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),gen_random_uuid(),
  (SELECT organization_workspace_id FROM fixture_0134_purge_org));
SET LOCAL session_replication_role=replica;
UPDATE app_private.organization_deletion_current
SET effective_at_utc=transaction_timestamp()-interval '721 hours',purge_after_utc=transaction_timestamp()-interval '1 hour'
WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0134_purge_org);
UPDATE app_private.organization_deletion_request_claims claim
SET effective_at_utc=cycle.effective_at_utc,purge_after_utc=cycle.purge_after_utc
FROM app_private.organization_deletion_current cycle
WHERE claim.request_id=cycle.deletion_request_id
  AND cycle.organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0134_purge_org);
UPDATE app_private.organization_deletion_audit_events audit
SET occurred_at_utc=cycle.effective_at_utc FROM app_private.organization_deletion_current cycle
WHERE audit.request_id=cycle.deletion_request_id
  AND cycle.organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0134_purge_org);
UPDATE app_data.workspaces workspace SET deleted_at=cycle.effective_at_utc
FROM app_private.organization_deletion_current cycle
WHERE workspace.workspace_id=cycle.organization_workspace_id
  AND workspace.workspace_id=(SELECT organization_workspace_id FROM fixture_0134_purge_org);
SET LOCAL session_replication_role=origin;

CREATE TEMP TABLE fixture_0134_purge_before(relation_name text,row_data jsonb);
DO $snapshot$
DECLARE relation_name text;
BEGIN
  FOR relation_name IN SELECT format('%I.%I',namespace.nspname,relation.relname)
    FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
    WHERE namespace.nspname IN ('app_data','app_private') AND relation.relkind='r' LOOP
    EXECUTE format('INSERT INTO fixture_0134_purge_before SELECT %L,to_jsonb(t) FROM %s t',relation_name,relation_name);
  END LOOP;
END
$snapshot$;

DO $collection$
BEGIN
  IF (SELECT count(*) FROM app_private.organization_purge_requests_v1(
      (SELECT organization_workspace_id FROM fixture_0134_purge_org))
      WHERE lock_rank=14 AND lock_namespace='personal-history-contribution-confirmation'
        AND claim_family='personal-history-contribution-confirmation'
        AND request_uuid=(SELECT request_id FROM fixture_0134_purge_request)) <> 1 THEN
    RAISE EXCEPTION '0134 contribution request lock collection drift';
  END IF;
END
$collection$;

SELECT pg_temp.expect_0134_purge_failure('55000',$statement$
  DO $cross_root$
  BEGIN
    SET LOCAL session_replication_role=replica;
    UPDATE app_private.organization_historical_contact_copies_v1
    SET target_project_id=(SELECT project_id FROM fixture_0134_purge_other_project)
    WHERE copy_id=(SELECT copy_id FROM fixture_0134_purge_copy);
    SET LOCAL session_replication_role=origin;
    PERFORM app_private.finalize_organization_purge_v1(
      (SELECT organization_workspace_id FROM fixture_0134_purge_org),
      (SELECT deletion_request_id FROM fixture_0134_purge_cycle));
  END
  $cross_root$
$statement$);

CREATE FUNCTION pg_temp.fail_0134_final_workspace_delete() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF OLD.workspace_id=(SELECT organization_workspace_id FROM fixture_0134_purge_org) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='0134 injected final workspace delete failure';
  END IF;
  RETURN OLD;
END
$function$;
CREATE TRIGGER fixture_0134_final_delete_failure AFTER DELETE ON app_data.workspaces
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0134_final_workspace_delete();
SELECT pg_temp.expect_0134_purge_failure('P0001',
  'SELECT * FROM app_private.finalize_organization_purge_v1((SELECT organization_workspace_id FROM fixture_0134_purge_org),(SELECT deletion_request_id FROM fixture_0134_purge_cycle))');
DROP TRIGGER fixture_0134_final_delete_failure ON app_data.workspaces;

DO $rollback$
DECLARE checked_relation text; actual_rows jsonb; expected_rows jsonb;
BEGIN
  FOR checked_relation IN SELECT format('%I.%I',namespace.nspname,relation.relname)
    FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
    WHERE namespace.nspname IN ('app_data','app_private') AND relation.relkind='r' LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %s t',checked_relation) INTO actual_rows;
    SELECT coalesce(jsonb_agg(row_data ORDER BY row_data::text),'[]'::jsonb) INTO expected_rows
    FROM fixture_0134_purge_before saved WHERE saved.relation_name=checked_relation;
    IF actual_rows IS DISTINCT FROM expected_rows THEN
      RAISE EXCEPTION '0134 purge failure changed %',checked_relation;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations) THEN
    RAISE EXCEPTION '0134 purge failure retained authorization';
  END IF;
END
$rollback$;

CREATE TEMP TABLE fixture_0134_purge_completed AS
SELECT * FROM app_private.finalize_organization_purge_v1(
  (SELECT organization_workspace_id FROM fixture_0134_purge_org),
  (SELECT deletion_request_id FROM fixture_0134_purge_cycle));
CREATE TEMP TABLE fixture_0134_purge_retry AS
SELECT * FROM app_private.finalize_organization_purge_v1(
  (SELECT organization_workspace_id FROM fixture_0134_purge_org),
  (SELECT deletion_request_id FROM fixture_0134_purge_cycle));

DO $purged$
DECLARE saved record; preserved boolean;
BEGIN
  IF EXISTS (SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1
      WHERE target_project_id=(SELECT project_id FROM fixture_0134_purge_project))
    OR EXISTS (SELECT 1 FROM app_private.personal_history_contribution_previews_v1
      WHERE target_project_id=(SELECT project_id FROM fixture_0134_purge_project))
    OR EXISTS (SELECT 1 FROM app_private.organization_historical_contact_copies_v1
      WHERE target_project_id=(SELECT project_id FROM fixture_0134_purge_project))
    OR EXISTS (SELECT 1 FROM app_data.workspaces
      WHERE workspace_id=(SELECT organization_workspace_id FROM fixture_0134_purge_org))
    OR EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations) THEN
    RAISE EXCEPTION '0134 purge retained organization contribution dependencies';
  END IF;
  IF (SELECT count(*) FROM fixture_0134_purge_completed) <> 1
    OR EXISTS ((TABLE fixture_0134_purge_completed EXCEPT TABLE fixture_0134_purge_retry)
      UNION ALL (TABLE fixture_0134_purge_retry EXCEPT TABLE fixture_0134_purge_completed))
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_purge_request_tombstones tombstone
      CROSS JOIN fixture_0134_purge_completed completed
      WHERE tombstone.claim_family='personal-history-contribution-confirmation'
        AND tombstone.request_uuid=(SELECT request_id FROM fixture_0134_purge_request)
        AND tombstone.purge_completed_at_utc=completed.purge_completed_at_utc
        AND isfinite(tombstone.purge_completed_at_utc)) THEN
    RAISE EXCEPTION '0134 contribution completion tombstone or terminal retry drift';
  END IF;
  FOR saved IN TABLE fixture_0134_purge_preserved LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s t WHERE to_jsonb(t)=$1)',saved.relation_name)
    INTO preserved USING saved.row_data;
    IF NOT preserved THEN RAISE EXCEPTION '0134 purge changed preserved row in %',saved.relation_name; END IF;
  END LOOP;
END
$purged$;

CREATE TEMP TABLE fixture_0134_purge_retry_preview AS
SELECT * FROM app_private.preview_personal_history_contribution_v1(
  (SELECT app_user_id FROM fixture_0134_purge_actor),'0134-purge-source',
  (SELECT project_id FROM fixture_0134_purge_other_project));
SELECT pg_temp.expect_0134_purge_failure('22023',
  'SELECT * FROM app_private.confirm_personal_history_contribution_v1((SELECT app_user_id FROM fixture_0134_purge_actor),(SELECT request_id FROM fixture_0134_purge_request),(SELECT preview_id FROM fixture_0134_purge_retry_preview))');

ROLLBACK;
SELECT 'personal history contribution organization purge fixtures: passed' AS result;
