-- Synthetic snapshot regression. All tables and rows roll back.
\set ON_ERROR_STOP on
BEGIN;
\ir shared/database_state.sql

CREATE FUNCTION pg_temp.legacy_database_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; result jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT schemaname,tablename FROM pg_catalog.pg_tables
    WHERE schemaname IN ('app_data','app_private') ORDER BY schemaname,tablename LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t',
      relation.schemaname,relation.tablename) INTO rows;
    result := result || jsonb_build_object(relation.schemaname || '.' || relation.tablename,rows);
  END LOOP;
  RETURN result;
END $function$;

CREATE TABLE app_data."fixture state ""测试"(value text,detail jsonb,optional text);
CREATE TABLE app_private."fixture state ""测试"(value text);
CREATE TABLE public.fixture_state_excluded(value text);
INSERT INTO app_data."fixture state ""测试" VALUES
  ('z','{"n":1}',NULL),('a',NULL,E'line\n汉字'),('a',NULL,E'line\n汉字');
INSERT INTO public.fixture_state_excluded VALUES ('outside app schemas');
CREATE TABLE app_data.fixture_state_partitioned(value integer) PARTITION BY RANGE(value);
CREATE TABLE app_data.fixture_state_partition_leaf PARTITION OF app_data.fixture_state_partitioned FOR VALUES FROM (0) TO (10);
INSERT INTO app_data.fixture_state_partitioned VALUES (1);
CREATE TEMP TABLE fixture_state_before AS SELECT pg_temp.fixture_database_state() AS document;

DO $check$
DECLARE document jsonb := (SELECT document FROM fixture_state_before);
BEGIN
  IF document IS DISTINCT FROM pg_temp.legacy_database_state() THEN
    RAISE EXCEPTION '0000 full snapshot differs from the legacy table-by-table result';
  END IF;
  IF document->'app_data.fixture state "测试' IS DISTINCT FROM
    '[{"value":"a","detail":null,"optional":"line\n汉字"},{"value":"a","detail":null,"optional":"line\n汉字"},{"value":"z","detail":{"n":1},"optional":null}]'::jsonb
    OR document->'app_private.fixture state "测试' IS DISTINCT FROM '[]'::jsonb
    OR document->'app_data.fixture_state_partitioned' IS DISTINCT FROM '[{"value":1}]'::jsonb
    OR document->'app_data.fixture_state_partition_leaf' IS DISTINCT FROM '[{"value":1}]'::jsonb
    OR document ? 'public.fixture_state_excluded' OR document ? 'pg_temp.fixture_state_before' THEN
    RAISE EXCEPTION '0000 snapshot lost values, duplicates, order, empty tables, or schema coverage';
  END IF;
END $check$;

UPDATE app_data."fixture state ""测试" SET optional='changed without changing row count' WHERE value='z';
DO $check$
BEGIN
  IF (SELECT document FROM fixture_state_before) IS NOT DISTINCT FROM pg_temp.fixture_database_state() THEN
    RAISE EXCEPTION '0000 snapshot did not detect a row value change';
  END IF;
END $check$;
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only=on;
DO $check$
BEGIN
  IF current_setting('transaction_read_only')<>'on' OR pg_temp.fixture_database_state() IS NULL THEN
    RAISE EXCEPTION '0000 snapshot did not run in READ ONLY';
  END IF;
END $check$;
ROLLBACK TO readonly_scope;
RELEASE SAVEPOINT readonly_scope;
ROLLBACK;
