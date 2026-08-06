-- 0014_questionnaire_draft_upgrades.sql
--
-- A questionnaire upgrade creates a second private draft. The source remains
-- intact until its owner explicitly abandons it. Store the relationship in a
-- constrained column as well as the sync document so retries and other devices
-- cannot erase or forge the source relationship.

ALTER TABLE app_data.contact_drafts
  ADD COLUMN upgraded_from_draft_id text,
  ADD CONSTRAINT contact_drafts_upgrade_source_valid CHECK (
    upgraded_from_draft_id IS NULL
    OR (
      length(btrim(upgraded_from_draft_id)) > 0
      AND upgraded_from_draft_id <> draft_id
    )
  ),
  ADD CONSTRAINT contact_drafts_upgrade_source_owner_fk
    FOREIGN KEY (app_user_id, upgraded_from_draft_id)
    REFERENCES app_data.contact_drafts (app_user_id, draft_id)
    ON DELETE RESTRICT
    DEFERRABLE INITIALLY IMMEDIATE;

CREATE INDEX contact_drafts_upgrade_source
  ON app_data.contact_drafts (app_user_id, upgraded_from_draft_id)
  WHERE upgraded_from_draft_id IS NOT NULL;

CREATE FUNCTION app_data.capture_questionnaire_draft_upgrade_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  source_value text;
  source_type text;
BEGIN
  IF NEW.content ? 'upgradedFromDraftId' THEN
    source_type := jsonb_typeof(NEW.content->'upgradedFromDraftId');
    IF source_type = 'string' THEN
      source_value := NULLIF(btrim(NEW.content->>'upgradedFromDraftId'), '');
      IF source_value IS NULL THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'draft upgrade source cannot be blank';
      END IF;
    ELSIF source_type IS DISTINCT FROM 'null' THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'draft upgrade source must be a string or null';
    END IF;
  END IF;

  IF source_value = NEW.draft_id THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'draft cannot be upgraded from itself';
  END IF;
  IF TG_OP = 'UPDATE'
    AND source_value IS DISTINCT FROM OLD.upgraded_from_draft_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'draft upgrade source is immutable';
  END IF;

  IF source_value IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM app_data.contact_drafts AS source_draft
    WHERE source_draft.app_user_id = NEW.app_user_id
      AND source_draft.draft_id = source_value
      AND source_draft.workspace_id = NEW.workspace_id
      AND source_draft.project_id = NEW.project_id
      AND source_draft.questionnaire_version_id <>
        NEW.questionnaire_version_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23503',
      MESSAGE = 'draft upgrade source is unavailable in this owner and project';
  END IF;

  NEW.upgraded_from_draft_id := source_value;
  RETURN NEW;
END
$function$;

CREATE TRIGGER contact_drafts_capture_upgrade_source
BEFORE INSERT OR UPDATE OF content, upgraded_from_draft_id
ON app_data.contact_drafts
FOR EACH ROW
EXECUTE FUNCTION app_data.capture_questionnaire_draft_upgrade_source();

REVOKE ALL ON FUNCTION
  app_data.capture_questionnaire_draft_upgrade_source()
  FROM PUBLIC;

COMMENT ON COLUMN app_data.contact_drafts.upgraded_from_draft_id IS
  'Owner-private immutable source draft for an explicit questionnaire upgrade.';
