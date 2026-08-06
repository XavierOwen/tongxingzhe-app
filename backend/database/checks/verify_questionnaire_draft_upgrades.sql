\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute
    WHERE attrelid = 'app_data.contact_drafts'::regclass
      AND attname = 'upgraded_from_draft_id'
      AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'draft upgrade source column is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = 'app_data.contact_drafts'::regclass
      AND conname = 'contact_drafts_upgrade_source_owner_fk'
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'owner-scoped draft upgrade foreign key is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid = 'app_data.contact_drafts'::regclass
      AND tgname = 'contact_drafts_capture_upgrade_source'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'draft upgrade source trigger is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_indexes
    WHERE schemaname = 'app_data'
      AND indexname = 'contact_drafts_upgrade_source'
      AND indexdef LIKE '%WHERE (upgraded_from_draft_id IS NOT NULL)%'
  ) THEN
    RAISE EXCEPTION 'draft upgrade source index is missing';
  END IF;
  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.capture_questionnaire_draft_upgrade_source()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can call the draft upgrade trigger directly';
  END IF;
  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0014_questionnaire_draft_upgrades'
  ) <> 1 THEN
    RAISE EXCEPTION 'draft upgrade migration was not recorded once';
  END IF;
END
$check$;
