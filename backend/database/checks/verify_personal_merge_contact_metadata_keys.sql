\set ON_ERROR_STOP on
DO $check$
DECLARE
  mapping regclass := 'app_private.personal_merge_contact_keys_v1'::regclass;
  binder regprocedure := 'app_private.assign_personal_merge_contact_key_v1()'::regprocedure;
  sequence_name regclass; expected_owner oid; relation regclass; item record; columns text[];
  key_attribute smallint; raw_attribute smallint; map_key smallint; map_raw smallint;
BEGIN
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
    WHERE oid='app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)'::regprocedure;
  SELECT array_agg(attname::text ORDER BY attnum) INTO columns FROM pg_attribute WHERE attrelid=mapping AND attnum>0 AND NOT attisdropped;
  SELECT attnum INTO STRICT map_key FROM pg_attribute WHERE attrelid=mapping AND attname='contact_identity_key' AND attnotnull AND atttypid='int8'::regtype AND attidentity='a';
  SELECT attnum INTO STRICT map_raw FROM pg_attribute WHERE attrelid=mapping AND attname='contact_id' AND attnotnull AND atttypid='text'::regtype;
  IF columns IS DISTINCT FROM ARRAY['contact_id','contact_identity_key']
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=mapping AND contype='p' AND conkey=ARRAY[map_raw])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=mapping AND conname='pmck_contact_key_key' AND contype='u' AND conkey=ARRAY[map_key])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=mapping AND conname='pmck_contact_key_identity_key' AND contype='u' AND conkey=ARRAY[map_key,map_raw])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=mapping AND conname='pmck_contact_fk' AND contype='f'
      AND confrelid='app_data.contacts'::regclass AND conkey=ARRAY[map_raw] AND confdeltype='c' AND convalidated)
  THEN RAISE EXCEPTION '0161 exact private contact identity or cascade constraints drift'; END IF;
  sequence_name := pg_get_serial_sequence(mapping::text,'contact_identity_key')::regclass;
  FOREACH relation IN ARRAY ARRAY[mapping,sequence_name] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid=relation AND relowner=expected_owner)
      OR EXISTS (SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault(CASE WHEN c.relkind='S' THEN 's'::"char" ELSE 'r'::"char" END,c.relowner))) acl
        WHERE c.oid=relation AND acl.grantee<>c.relowner)
      OR (relation=mapping AND has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
      OR (relation=sequence_name AND has_sequence_privilege('tongxingzhe_runtime',relation,'USAGE,SELECT,UPDATE'))
    THEN RAISE EXCEPTION '0161 contact identity map or sequence owner/ACL drift: %',relation; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=binder AND proowner=expected_owner AND prosecdef AND provolatile='v'
      AND prorettype='trigger'::regtype AND proconfig=ARRAY['search_path=pg_catalog'])
    OR has_function_privilege('tongxingzhe_runtime',binder,'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      WHERE p.oid=binder AND acl.grantee<>p.proowner)
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=mapping AND NOT tgisinternal AND tgenabled='O' AND tgtype=19
      AND tgfoid='app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure)
  THEN RAISE EXCEPTION '0161 private binder or immutable map UPDATE guard drift'; END IF;

  FOR item IN SELECT * FROM (VALUES
    ('personal_merge_contact_applications_v1','pmca_contact_key_fk',ARRAY['actor_app_user_id','request_id','contact_identity_key']),
    ('personal_merge_contact_history_applications_v1','pmch_contact_key_fk',ARRAY['actor_app_user_id','request_id','contact_identity_key','original_revision_number']),
    ('personal_merge_contact_current_revisions_v1','pmccr_contact_key_fk',ARRAY['actor_app_user_id','request_id','contact_identity_key']),
    ('personal_merge_contact_current_choices_v1','pmccc_contact_key_fk',ARRAY['actor_app_user_id','request_id','contact_identity_key','source_target_id'])
  ) AS metadata(table_name,pair_fk,key_columns) LOOP
    relation := ('app_private.'||item.table_name)::regclass;
    SELECT attnum INTO STRICT key_attribute FROM pg_attribute WHERE attrelid=relation AND attname='contact_identity_key' AND attnotnull AND atttypid='int8'::regtype;
    SELECT attnum INTO STRICT raw_attribute FROM pg_attribute WHERE attrelid=relation AND attname='contact_id' AND attnotnull AND atttypid='text'::regtype;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=relation AND conname=item.pair_fk AND contype='f' AND confrelid=mapping
        AND conkey=ARRAY[key_attribute,raw_attribute] AND confkey=ARRAY[map_key,map_raw] AND convalidated)
      OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=relation AND tgname=replace(item.table_name,'_v1','')||'_key'
        AND NOT tgisinternal AND tgenabled='O' AND tgtype=7 AND tgfoid=binder)
    THEN RAISE EXCEPTION '0161 raw contact/key FK or INSERT binder drift: %',relation; END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=relation AND contype IN ('p','u') AND raw_attribute=ANY(conkey)
        AND (SELECT attnum FROM pg_attribute WHERE attrelid=relation AND attname='actor_app_user_id')=ANY(conkey)
        AND (SELECT attnum FROM pg_attribute WHERE attrelid=relation AND attname='request_id')=ANY(conkey))
      OR NOT EXISTS (SELECT 1 FROM pg_constraint constraint_row WHERE conrelid=relation AND contype IN ('p','u')
      AND (SELECT array_agg(attribute.attname::text ORDER BY key.ordinality)
        FROM unnest(constraint_row.conkey) WITH ORDINALITY key(attnum,ordinality)
        JOIN pg_attribute attribute ON attribute.attrelid=relation AND attribute.attnum=key.attnum)=item.key_columns)
    THEN RAISE EXCEPTION '0161 contact metadata identity key is not bounded: %',relation; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_constraint constraint_row
    JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attname='contact_id'
    WHERE constraint_row.conrelid=ANY(ARRAY['app_private.personal_merge_contact_applications_v1'::regclass,
      'app_private.personal_merge_contact_history_applications_v1'::regclass,'app_private.personal_merge_contact_current_revisions_v1'::regclass])
      AND constraint_row.contype='f' AND attribute.attnum=ANY(constraint_row.conkey)
      AND constraint_row.confrelid IN ('app_data.contact_revisions'::regclass,'app_data.contact_target_links'::regclass))<>8
    OR NOT EXISTS (SELECT 1 FROM pg_constraint constraint_row
      WHERE constraint_row.conrelid='app_private.personal_merge_contact_history_applications_v1'::regclass AND contype='u'
        AND (SELECT array_agg(attribute.attname::text ORDER BY key.ordinality) FROM unnest(constraint_row.conkey) WITH ORDINALITY key(attnum,ordinality)
          JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key.attnum)=ARRAY['contact_id','to_revision_number'])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='app_private.personal_merge_contact_current_choices_v1'::regclass
      AND conname='pmcr_choice_current_fk' AND contype='f' AND confrelid='app_private.personal_merge_contact_current_revisions_v1'::regclass
      AND conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=conrelid AND attname='actor_app_user_id'),
        (SELECT attnum FROM pg_attribute WHERE attrelid=conrelid AND attname='request_id'),
        (SELECT attnum FROM pg_attribute WHERE attrelid=conrelid AND attname='contact_identity_key')])
  THEN RAISE EXCEPTION '0161 ordinary raw lineage FKs or bounded current-choice FK drift'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0161_personal_merge_contact_metadata_keys')<>1 THEN
    RAISE EXCEPTION '0161 contact metadata key migration was not recorded once';
  END IF;
END
$check$;
SELECT 'personal merge exact contact identity, metadata keys, and private privileges: passed' AS result;
