\set ON_ERROR_STOP on
\set fixture_0160_definitions_only true
\ir ../0160_personal_merge_bounded_child_commands.sql
\unset fixture_0160_definitions_only

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) IS DISTINCT FROM '0160_personal_merge_bounded_child_commands' THEN
    RAISE EXCEPTION 'contact metadata key upgrade requires the real 0160 baseline';
  END IF;
END
$baseline$;
CREATE TABLE public.fixture_0160_metadata_cases(kind text,fixture jsonb,completed_at_utc timestamptz);
DO $ordinary_live_data$
DECLARE flow integer; size integer; contact_key text; c jsonb; completed timestamptz;
BEGIN
  FOREACH flow IN ARRAY ARRAY[128,130,142,143] LOOP
    SELECT left(string_agg(md5('0161-upgrade-pending/'||flow||'/'||i),'' ORDER BY i),2670)
      INTO contact_key FROM generate_series(1,100) i;
    c := pg_temp.fixture_0160_seed(flow,contact_key,'0161-upgrade-pending-'||flow);
    INSERT INTO public.fixture_0160_metadata_cases VALUES('pending',c,NULL);
    FOREACH size IN ARRAY ARRAY[64,2600] LOOP
      SELECT left(string_agg(md5('0161-upgrade-completed/'||flow||'/'||size||'/'||i),'' ORDER BY i),size)
        INTO contact_key FROM generate_series(1,100) i;
      c := pg_temp.fixture_0160_seed(flow,contact_key,'0161-upgrade-completed-'||flow||'-'||size);
      completed := pg_temp.fixture_0160_confirm(c);
      IF completed IS NULL THEN RAISE EXCEPTION '0160 ordinary completed receipt is missing for flow % bytes %',flow,size; END IF;
      INSERT INTO public.fixture_0160_metadata_cases VALUES('completed',c,completed);
    END LOOP;
  END LOOP;
END
$ordinary_live_data$;

CREATE TABLE public.fixture_0160_metadata_columns AS
SELECT tables.schemaname,tables.tablename,array_agg(attribute.attname::text ORDER BY attribute.attnum) AS original_columns
FROM pg_catalog.pg_tables tables
JOIN pg_catalog.pg_namespace namespace ON namespace.nspname=tables.schemaname
JOIN pg_catalog.pg_class relation ON relation.relnamespace=namespace.oid AND relation.relname=tables.tablename
JOIN pg_catalog.pg_attribute attribute ON attribute.attrelid=relation.oid AND attribute.attnum>0 AND NOT attribute.attisdropped
WHERE tables.schemaname IN ('app_data','app_private')
GROUP BY tables.schemaname,tables.tablename;

-- Compare every original field while allowing the migration to add its derived key column.
CREATE FUNCTION public.fixture_0160_metadata_original_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE statements text; result jsonb;
BEGIN
  SELECT string_agg(format(
    'SELECT %L::text AS relation_name,coalesce(jsonb_agg(original_row ORDER BY original_row::text),''[]''::jsonb) AS contents FROM (SELECT (SELECT jsonb_object_agg(field.key,field.value) FROM jsonb_each(to_jsonb(t)) field WHERE field.key=ANY(%L::text[])) AS original_row FROM %I.%I t) rows',
    schemaname||'.'||tablename,original_columns,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)
    INTO statements FROM public.fixture_0160_metadata_columns;
  EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM ('||statements||') snapshots' INTO result;
  RETURN result;
END
$function$;
CREATE TABLE public.fixture_0160_metadata_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0160_metadata_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
DO $projection$
BEGIN
  IF public.fixture_0160_metadata_original_state() IS DISTINCT FROM (SELECT business_state FROM public.fixture_0160_metadata_snapshot) THEN
    RAISE EXCEPTION '0160 original-column projection differs from the complete baseline snapshot';
  END IF;
END
$projection$;
COMMIT;

CREATE FUNCTION public.fixture_0160_metadata_assert_upgrade() RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE frozen public.fixture_0160_metadata_snapshot%ROWTYPE; item record; before_replay jsonb;
BEGIN
  SELECT * INTO STRICT frozen FROM public.fixture_0160_metadata_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>frozen.migration_count+1
    OR public.fixture_0160_metadata_original_state() IS DISTINCT FROM frozen.business_state
    OR EXISTS (SELECT 1 FROM public.fixture_0160_metadata_catalog old
      LEFT JOIN pg_catalog.pg_proc live ON live.oid=old.oid
      WHERE old.catalog_row IS DISTINCT FROM to_jsonb(live))
  THEN RAISE EXCEPTION '0160 to 0161 changed original fields, old function identities, or definitions'; END IF;
  before_replay := pg_temp.fixture_database_state();
  FOR item IN SELECT * FROM public.fixture_0160_metadata_cases WHERE kind='completed' LOOP
    IF pg_temp.fixture_0160_confirm(item.fixture) IS DISTINCT FROM item.completed_at_utc THEN
      RAISE EXCEPTION '0161 changed an ordinary 0160 completed receipt';
    END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0161 completed receipt replay changed metadata, commands, or facts';
  END IF;
  FOR item IN SELECT * FROM public.fixture_0160_metadata_cases WHERE kind='pending' LOOP
    PERFORM pg_temp.fixture_0160_assert(item.fixture);
  END LOOP;
END
$function$;
