\set ON_ERROR_STOP on

DO $check$
DECLARE
  anonymize_function regprocedure := 'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)'::regprocedure;
  trusted_owner oid;
  source text;
  redaction_clause constant text := $clause$reason_detail = CASE WHEN reason_code = 'other'
        THEN '[已匿名化]' ELSE NULL END$clause$;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0139_other_relationship_reason_redaction') <> 1 THEN
    RAISE EXCEPTION '0139 migration was not recorded once';
  END IF;

  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT prosrc INTO STRICT source FROM pg_catalog.pg_proc
  WHERE oid = anonymize_function AND proowner = trusted_owner
    AND prosecdef AND provolatile = 'v'
    AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[];

  IF has_function_privilege('tongxingzhe_runtime', anonymize_function, 'EXECUTE')
    OR has_function_privilege('public', anonymize_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'internal relationship anonymizer ACL boundary drifted';
  END IF;

  IF length(source) - length(replace(source, redaction_clause, '')) <> length(redaction_clause)
    OR position('SET follow_up_note = NULL' IN source) = 0
    OR position('requested_follow_up_note = NULL' IN source) = 0
    OR position('SET proposed_follow_up_note = NULL, proposed_reason_detail = NULL' IN source) = 0 THEN
    RAISE EXCEPTION '0139 relationship revision or conflict redaction drifted';
  END IF;
END
$check$;

SELECT 'other relationship reason redaction: passed' AS result;
