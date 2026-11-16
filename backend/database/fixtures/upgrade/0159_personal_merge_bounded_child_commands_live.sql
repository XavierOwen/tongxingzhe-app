\set ON_ERROR_STOP on
\set fixture_0160_definitions_only true
\ir ../0160_personal_merge_bounded_child_commands.sql

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) IS DISTINCT FROM '0159_personal_merge_project_relationship_unicode_text' THEN
    RAISE EXCEPTION 'bounded child command upgrade requires the real 0159 baseline';
  END IF;
END
$baseline$;
CREATE TABLE public.fixture_0159_bounded_cases(kind text,fixture jsonb,completed_at_utc timestamptz);
DO $ordinary_live_data$
DECLARE flow integer; contact_key text; c jsonb; confirmed timestamptz;
BEGIN
  FOREACH flow IN ARRAY ARRAY[128,130,142,143] LOOP
    SELECT left(string_agg(md5('upgrade/'||flow||'/'||i),'' ORDER BY i),2600) INTO contact_key FROM generate_series(1,100) i;
    c := pg_temp.fixture_0160_seed(flow,contact_key,'upgrade-pending-'||flow);
    INSERT INTO public.fixture_0159_bounded_cases VALUES('pending',c,NULL);
  END LOOP;
  FOREACH flow IN ARRAY ARRAY[128,130] LOOP
    c := pg_temp.fixture_0160_seed(flow,'legacy-'||flow||repeat('x',3000),'upgrade-legacy-'||flow);
    confirmed := pg_temp.fixture_0160_confirm(c);
    IF confirmed IS NULL THEN RAISE EXCEPTION '0159 compressible long v1 receipt was not completed'; END IF;
    IF flow=130 AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_current_revisions_v1 receipt
      WHERE receipt.actor_app_user_id=(c->>'app_user_id')::uuid AND receipt.request_id=(c->>'request_id')::uuid
        AND receipt.child_command_id='personal-merge-contact-resolve-v1:'||(c->>'request_id')||':current:'||octet_length(c->>'contact_id')||':'||(c->>'contact_id')) THEN
      RAISE EXCEPTION '0159 legacy current child was not the complete v1 ID';
    END IF;
    INSERT INTO public.fixture_0159_bounded_cases VALUES('legacy',c,confirmed);
  END LOOP;
END
$ordinary_live_data$;
CREATE TABLE public.fixture_0159_bounded_catalog AS
SELECT oid,to_jsonb(procedure) AS catalog_row FROM pg_catalog.pg_proc procedure
WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0159_bounded_snapshot AS
SELECT pg_temp.fixture_database_state() AS business_state,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0159_bounded_assert_upgrade() RETURNS void LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE frozen public.fixture_0159_bounded_snapshot%ROWTYPE; item record; before_replay jsonb;
BEGIN
  SELECT * INTO STRICT frozen FROM public.fixture_0159_bounded_snapshot;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>frozen.migration_count+1
    OR pg_temp.fixture_database_state() IS DISTINCT FROM frozen.business_state
    OR EXISTS (SELECT 1 FROM public.fixture_0159_bounded_catalog old
      LEFT JOIN pg_catalog.pg_proc live ON live.oid=old.oid
      WHERE CASE WHEN old.catalog_row->>'proname' IN (
        'confirm_unassigned_personal_merge_contacts_v1','confirm_personal_merge_contact_resolutions_v1',
        'personal_merge_contact_resolution_proof_v1','apply_personal_merge_contact_resolutions_v1',
        'confirm_personal_merge_mixed_resolutions_v1','confirm_personal_merge_mixed_resolutions_v2')
        THEN old.catalog_row-'prosrc' IS DISTINCT FROM to_jsonb(live)-'prosrc'
        ELSE old.catalog_row IS DISTINCT FROM to_jsonb(live) END)
  THEN RAISE EXCEPTION '0159→0160 changed old business rows, OIDs, owners, ACLs, or unrelated function definitions'; END IF;
  before_replay := pg_temp.fixture_database_state();
  FOR item IN SELECT * FROM public.fixture_0159_bounded_cases WHERE kind='legacy' LOOP
    IF pg_temp.fixture_0160_confirm(item.fixture) IS DISTINCT FROM item.completed_at_utc THEN
      RAISE EXCEPTION '0160 changed the original compressible long-ID completed receipt';
    END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0160 legacy completed v1 replay rewrote old commands, receipts, or facts';
  END IF;
  FOR item IN SELECT * FROM public.fixture_0159_bounded_cases WHERE kind='pending' LOOP
    PERFORM pg_temp.fixture_0160_assert(item.fixture);
  END LOOP;
END
$function$;
