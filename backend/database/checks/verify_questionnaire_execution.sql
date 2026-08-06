DO $check$
DECLARE
  function_name text;
BEGIN
  IF has_table_privilege(
    'tongxingzhe_runtime', 'app_data.questionnaire_questions', 'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime', 'app_data.questionnaire_options', 'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime can read questionnaire definition tables directly';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    'app_data.read_published_questionnaire(uuid,uuid,uuid,uuid)',
    'app_data.apply_contact_submit_v2(uuid,text,integer,text,text,text,integer,jsonb)',
    'app_data.apply_contact_revise_v2(uuid,text,integer,text,text,text,integer,jsonb)',
    'app_data.apply_contact_conflict_resolution_v2(uuid,text,integer,text,text,text,integer,jsonb)',
    'app_data.apply_contact_void_v2(uuid,text,integer,text,text,text,integer,jsonb)',
    'app_data.apply_draft_upsert_v2(uuid,text,integer,text,text,text,integer,jsonb)'
  ]
  LOOP
    IF NOT has_function_privilege(
      'tongxingzhe_runtime', function_name, 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'runtime cannot execute %', function_name;
    END IF;
  END LOOP;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_answer_errors(uuid,jsonb,boolean)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.insert_questionnaire_answers(text,integer,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_revision_payload(jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.finalize_questionnaire_revision(text,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can execute a private questionnaire helper';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'app_data'
      AND procedure_row.proname IN (
        'read_published_questionnaire',
        'apply_contact_submit_v2',
        'apply_contact_revise_v2',
        'apply_contact_conflict_resolution_v2',
        'apply_contact_void_v2',
        'apply_draft_upsert_v2'
      )
      AND NOT procedure_row.prosecdef
  ) THEN
    RAISE EXCEPTION 'questionnaire entry point is not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0011_questionnaire_execution'
  ) <> 1 THEN
    RAISE EXCEPTION 'questionnaire migration was not recorded exactly once';
  END IF;
END
$check$;
