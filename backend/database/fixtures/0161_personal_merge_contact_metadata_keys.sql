\set ON_ERROR_STOP on
\set fixture_0160_definitions_only true
\ir 0160_personal_merge_bounded_child_commands.sql
\unset fixture_0160_definitions_only

CREATE FUNCTION pg_temp.fixture_0161_identity(c jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE relation text; mapped bigint; actual_count integer; wrong_count integer; expected_count integer;
BEGIN
  SELECT contact_identity_key INTO STRICT mapped FROM app_private.personal_merge_contact_keys_v1 WHERE contact_id=c->>'contact_id';
  FOREACH relation IN ARRAY ARRAY['personal_merge_contact_applications_v1','personal_merge_contact_history_applications_v1',
    'personal_merge_contact_current_revisions_v1','personal_merge_contact_current_choices_v1'] LOOP
    expected_count := CASE WHEN ((c->>'flow')::integer=128)=(relation='personal_merge_contact_applications_v1') THEN 1 ELSE 0 END;
    EXECUTE format('SELECT count(*),count(*) FILTER (WHERE contact_identity_key IS DISTINCT FROM $2) FROM app_private.%I WHERE contact_id=$1',relation)
      INTO actual_count,wrong_count USING c->>'contact_id',mapped;
    IF actual_count<>expected_count OR wrong_count<>0 THEN
      RAISE EXCEPTION '0161 exact contact key or reuse differs for %',relation;
    END IF;
  END LOOP;
END
$function$;
CREATE FUNCTION pg_temp.fixture_0161_wrong_key() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  SELECT contact_identity_key INTO STRICT NEW.contact_identity_key FROM pg_temp.fixture_0161_foreign_key;
  RETURN NEW;
END
$function$;

\if :{?fixture_0161_definitions_only}
\else
BEGIN;
SET LOCAL TIME ZONE 'UTC';
-- A real 0160 baseline reaches the private application index after ordinary writers and stage succeed.
DO $first_confirmation$
DECLARE contact_key text;
BEGIN
  SELECT left(string_agg(md5('0161-first/'||i),'' ORDER BY i),2670) INTO contact_key FROM generate_series(1,100) i;
  PERFORM pg_temp.fixture_0160_assert(pg_temp.fixture_0160_seed(128,contact_key,'0161-first-confirmation'));
END
$first_confirmation$;

DO $boundaries$
DECLARE flow integer; size integer; contact_key text; c jsonb;
BEGIN
  FOREACH flow IN ARRAY ARRAY[128,130,142,143] LOOP
    FOREACH size IN ARRAY ARRAY[64,2600,2640,2650,2664,2670] LOOP
      SELECT left(string_agg(md5('0161/'||flow||'/'||size||'/'||i),'' ORDER BY i),size)
        INTO contact_key FROM generate_series(1,100) i;
      c := pg_temp.fixture_0160_seed(flow,contact_key,'0161-'||flow||'-'||size);
      PERFORM pg_temp.fixture_0160_assert(c);
      PERFORM pg_temp.fixture_0161_identity(c);
    END LOOP;
  END LOOP;
END
$boundaries$;

CREATE TEMP TABLE fixture_0161_foreign_key(contact_identity_key bigint) ON COMMIT DROP;
DO $foreign_key$
DECLARE c jsonb;
BEGIN
  c := pg_temp.fixture_0160_seed(130,'0161 foreign exact identity','0161-foreign-key');
  PERFORM pg_temp.fixture_0160_assert(c);
  INSERT INTO fixture_0161_foreign_key SELECT contact_identity_key FROM app_private.personal_merge_contact_keys_v1 WHERE contact_id=c->>'contact_id';
END
$foreign_key$;
DO $explicit_key_and_rollback$
DECLARE relation text; flow integer; c jsonb; contact_key text; before_error jsonb; actual text; failed_constraint text;
BEGIN
  FOREACH relation IN ARRAY ARRAY['personal_merge_contact_applications_v1','personal_merge_contact_history_applications_v1',
    'personal_merge_contact_current_revisions_v1','personal_merge_contact_current_choices_v1'] LOOP
    flow := CASE WHEN relation='personal_merge_contact_applications_v1' THEN 128 ELSE 130 END;
    SELECT left(string_agg(md5('0161-wrong/'||relation||'/'||i),'' ORDER BY i),2670)
      INTO contact_key FROM generate_series(1,100) i;
    c := pg_temp.fixture_0160_seed(flow,contact_key,'0161-wrong-'||relation);
    -- This trigger supplies a nonnull wrong key before the product INSERT binder.
    EXECUTE format('CREATE TRIGGER aaa_fixture_0161_wrong_key BEFORE INSERT ON app_private.%I FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0161_wrong_key()',relation);
    before_error := pg_temp.fixture_database_state(); actual := NULL; failed_constraint := NULL;
    BEGIN PERFORM pg_temp.fixture_0160_confirm(c);
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE,failed_constraint=CONSTRAINT_NAME; END;
    IF actual IS DISTINCT FROM '23503' OR failed_constraint IS NULL OR failed_constraint NOT IN ('pmca_contact_key_fk','pmch_contact_key_fk',
      'pmccr_contact_key_fk','pmccc_contact_key_fk','pmcr_choice_current_fk') OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error THEN
      RAISE EXCEPTION '0161 explicit key/raw mismatch was overwritten or failed to roll back for %: %, %',relation,actual,failed_constraint;
    END IF;
    EXECUTE format('DROP TRIGGER aaa_fixture_0161_wrong_key ON app_private.%I',relation);
    PERFORM pg_temp.fixture_0160_assert(c);
    PERFORM pg_temp.fixture_0161_identity(c);
  END LOOP;
  FOREACH flow IN ARRAY ARRAY[128,130,142,143] LOOP
    SELECT left(string_agg(md5('0161-late/'||flow||'/'||i),'' ORDER BY i),2670)
      INTO contact_key FROM generate_series(1,100) i;
    c := pg_temp.fixture_0160_seed(flow,contact_key,'0161-late-'||flow);
    CREATE TRIGGER fixture_0161_end_fault BEFORE INSERT ON app_private.personal_target_merge_end_events_v1
      FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0160_end_fault();
    before_error := pg_temp.fixture_database_state(); actual := NULL;
    BEGIN PERFORM pg_temp.fixture_0160_confirm(c);
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
    IF actual IS DISTINCT FROM '23514' OR pg_temp.fixture_database_state() IS DISTINCT FROM before_error THEN
      RAISE EXCEPTION '0161 flow % late failure left a map key, child, or receipt: %',flow,actual;
    END IF;
    DROP TRIGGER fixture_0161_end_fault ON app_private.personal_target_merge_end_events_v1;
    PERFORM pg_temp.fixture_0160_assert(c);
    PERFORM pg_temp.fixture_0161_identity(c);
  END LOOP;
END
$explicit_key_and_rollback$;

DO $contact_cascade$
DECLARE cascade_contact text := '0161-isolated-contact-cascade'; mapped bigint;
BEGIN
  -- The isolated contact has no revisions or ledgers, so its existing child RESTRICT FKs do not block this cascade check.
  INSERT INTO app_data.contacts SELECT (jsonb_populate_record(NULL::app_data.contacts,
    to_jsonb(contact)||jsonb_build_object('contact_id',cascade_contact))).* FROM app_data.contacts contact LIMIT 1;
  INSERT INTO app_private.personal_merge_contact_keys_v1(contact_id) VALUES(cascade_contact) RETURNING contact_identity_key INTO mapped;
  DELETE FROM app_data.contacts WHERE contact_id=cascade_contact;
  IF EXISTS (SELECT 1 FROM app_private.personal_merge_contact_keys_v1 WHERE contact_identity_key=mapped) THEN
    RAISE EXCEPTION '0161 isolated contact deletion did not cascade to its private key';
  END IF;
END
$contact_cascade$;
ROLLBACK;
SELECT 'personal merge contact metadata key boundaries and exact replay: passed' AS result;
\endif
