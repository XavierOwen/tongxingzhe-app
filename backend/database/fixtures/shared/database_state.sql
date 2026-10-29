CREATE FUNCTION pg_temp.fixture_database_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE statements text; result jsonb;
BEGIN
  -- Aggregate once to avoid copying the growing database snapshot for every table.
  SELECT string_agg(format(
    'SELECT %L::text AS relation_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS contents FROM %I.%I t',
    schemaname || '.' || tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)
  INTO statements FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');
  IF statements IS NULL THEN RETURN '{}'::jsonb; END IF;
  EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM (' || statements || ') snapshots' INTO result;
  RETURN result;
END $function$;
