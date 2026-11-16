-- Keep exact TEXT identity while removing it from wider receipt keys.
LOCK TABLE app_private.personal_merge_contact_applications_v1,
  app_private.personal_merge_contact_history_applications_v1,
  app_private.personal_merge_contact_current_revisions_v1,
  app_private.personal_merge_contact_current_choices_v1 IN ACCESS EXCLUSIVE MODE;

CREATE TABLE app_private.personal_merge_contact_keys_v1 (
  contact_id text PRIMARY KEY,
  contact_identity_key bigint GENERATED ALWAYS AS IDENTITY,
  CONSTRAINT pmck_contact_fk FOREIGN KEY (contact_id)
    REFERENCES app_data.contacts(contact_id) ON DELETE CASCADE,
  CONSTRAINT pmck_contact_key_key UNIQUE (contact_identity_key),
  CONSTRAINT pmck_contact_key_identity_key UNIQUE (contact_identity_key, contact_id)
);

INSERT INTO app_private.personal_merge_contact_keys_v1(contact_id)
SELECT contact_id FROM (
  SELECT contact_id FROM app_private.personal_merge_contact_applications_v1
  UNION SELECT contact_id FROM app_private.personal_merge_contact_history_applications_v1
  UNION SELECT contact_id FROM app_private.personal_merge_contact_current_revisions_v1
  UNION SELECT contact_id FROM app_private.personal_merge_contact_current_choices_v1
) contacts ORDER BY contact_id COLLATE "C";

CREATE FUNCTION app_private.assign_personal_merge_contact_key_v1()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  IF NEW.contact_identity_key IS NULL THEN
    INSERT INTO app_private.personal_merge_contact_keys_v1(contact_id)
    VALUES (NEW.contact_id) ON CONFLICT (contact_id) DO NOTHING;
    SELECT mapping.contact_identity_key INTO STRICT NEW.contact_identity_key
    FROM app_private.personal_merge_contact_keys_v1 mapping WHERE mapping.contact_id = NEW.contact_id;
  END IF;
  RETURN NEW;
END
$function$;

-- Mapping updates are forbidden; native contact deletion must still cascade.
CREATE TRIGGER personal_merge_contact_keys_immutable BEFORE UPDATE
ON app_private.personal_merge_contact_keys_v1 FOR EACH ROW
EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

DO $receipt_keys$
DECLARE
  receipt record;
  immutable_trigger text;
BEGIN
  FOR receipt IN SELECT * FROM (VALUES
    ('personal_merge_contact_applications_v1', 'pmca_contact_key_fk'),
    ('personal_merge_contact_history_applications_v1', 'pmch_contact_key_fk'),
    ('personal_merge_contact_current_revisions_v1', 'pmccr_contact_key_fk'),
    ('personal_merge_contact_current_choices_v1', 'pmccc_contact_key_fk')
  ) receipts(relation_name, constraint_name)
  LOOP
    immutable_trigger := replace(receipt.relation_name, '_v1', '_immutable');
    EXECUTE format('ALTER TABLE app_private.%I ADD COLUMN contact_identity_key bigint', receipt.relation_name);
    -- The four exclusive locks exclude writers while only the new column is backfilled.
    EXECUTE format('ALTER TABLE app_private.%I DISABLE TRIGGER %I', receipt.relation_name, immutable_trigger);
    EXECUTE format('UPDATE app_private.%I receipt SET contact_identity_key = mapping.contact_identity_key
      FROM app_private.personal_merge_contact_keys_v1 mapping WHERE mapping.contact_id = receipt.contact_id', receipt.relation_name);
    EXECUTE format('ALTER TABLE app_private.%I ENABLE TRIGGER %I', receipt.relation_name, immutable_trigger);
    EXECUTE format('ALTER TABLE app_private.%I ALTER COLUMN contact_identity_key SET NOT NULL', receipt.relation_name);
    EXECUTE format('ALTER TABLE app_private.%I ADD CONSTRAINT %I FOREIGN KEY (contact_identity_key, contact_id)
      REFERENCES app_private.personal_merge_contact_keys_v1(contact_identity_key, contact_id)', receipt.relation_name, receipt.constraint_name);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT ON app_private.%I FOR EACH ROW
      EXECUTE FUNCTION app_private.assign_personal_merge_contact_key_v1()',
      replace(receipt.relation_name, '_v1', '_key'), receipt.relation_name);
  END LOOP;
END
$receipt_keys$;

ALTER TABLE app_private.personal_merge_contact_applications_v1
  DROP CONSTRAINT personal_merge_contact_applic_actor_app_user_id_request_id__key,
  ADD CONSTRAINT personal_merge_contact_applic_actor_app_user_id_request_id__key
    UNIQUE (actor_app_user_id, request_id, contact_identity_key);
ALTER TABLE app_private.personal_merge_contact_history_applications_v1
  DROP CONSTRAINT pmcr_history_original_once,
  ADD CONSTRAINT pmcr_history_original_once
    UNIQUE (actor_app_user_id, request_id, contact_identity_key, original_revision_number);

ALTER TABLE app_private.personal_merge_contact_current_choices_v1 DROP CONSTRAINT pmcr_choice_current_fk;
ALTER TABLE app_private.personal_merge_contact_current_revisions_v1
  DROP CONSTRAINT personal_merge_contact_current_revisions_v1_pkey,
  ADD CONSTRAINT personal_merge_contact_current_revisions_v1_pkey
    PRIMARY KEY (actor_app_user_id, request_id, contact_identity_key);
ALTER TABLE app_private.personal_merge_contact_current_choices_v1
  DROP CONSTRAINT personal_merge_contact_current_choices_v1_pkey,
  ADD CONSTRAINT personal_merge_contact_current_choices_v1_pkey
    PRIMARY KEY (actor_app_user_id, request_id, contact_identity_key, source_target_id),
  ADD CONSTRAINT pmcr_choice_current_fk FOREIGN KEY (actor_app_user_id, request_id, contact_identity_key)
    REFERENCES app_private.personal_merge_contact_current_revisions_v1(actor_app_user_id, request_id, contact_identity_key);

REVOKE ALL ON TABLE app_private.personal_merge_contact_keys_v1 FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON SEQUENCE app_private.personal_merge_contact_keys_v1_contact_identity_key_seq FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION app_private.assign_personal_merge_contact_key_v1() FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner name;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)'::regprocedure;
  EXECUTE format('ALTER TABLE app_private.personal_merge_contact_keys_v1 OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.assign_personal_merge_contact_key_v1() OWNER TO %I', trusted_owner);
END
$owner$;
