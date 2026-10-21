\set ON_ERROR_STOP on
DO $check$
DECLARE
  confirmer regprocedure:='app_private.confirm_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure;
  contact_apply regprocedure:='app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)'::regprocedure;
  project_apply regprocedure:='app_private.apply_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)'::regprocedure;
  fact_proof regprocedure:='app_private.personal_merge_project_relationship_resolution_fact_proof_v1(uuid,uuid)'::regprocedure;
  mixed_proof regprocedure:='app_private.personal_merge_mixed_resolution_proof_v1(uuid,uuid)'::regprocedure;
  receipt regclass:='app_private.personal_merge_mixed_resolution_requests_v1'::regclass;
  trusted_owner oid; candidate regprocedure;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0142_personal_merge_mixed_resolution_confirmation')<>1
  THEN RAISE EXCEPTION '0142 mixed resolution confirmation migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid='app_private.plan_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  IF has_schema_privilege('public','app_private','USAGE') OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
  THEN RAISE EXCEPTION '0142 private schema cannot be opened'; END IF;
  FOREACH candidate IN ARRAY ARRAY[confirmer,contact_apply,project_apply,fact_proof,mixed_proof] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=candidate AND proowner=trusted_owner AND prosecdef AND NOT proretset
      AND proconfig=ARRAY['search_path=pg_catalog']::text[]
      AND provolatile=CASE WHEN candidate IN (fact_proof,mixed_proof) THEN 's'::"char" ELSE 'v'::"char" END
      AND prorettype=CASE WHEN candidate IN (fact_proof,mixed_proof) THEN 'boolean'::regtype
        WHEN candidate=confirmer THEN 'timestamptz'::regtype ELSE 'void'::regtype END)
      OR has_function_privilege('public',candidate,'EXECUTE') OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
        WHERE p.oid=candidate AND acl.grantee<>p.proowner)
    THEN RAISE EXCEPTION '0142 function result, owner, volatility, security or ACL drift: %',candidate; END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=receipt AND relkind='r' AND relowner=trusted_owner)
    OR has_table_privilege('public',receipt,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime',receipt,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
      WHERE c.oid=receipt AND acl.grantee<>c.relowner)
    OR (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute WHERE attrelid=receipt AND attnum>0 AND NOT attisdropped)
      IS DISTINCT FROM ARRAY['actor_app_user_id','request_id','generation_id','resolution_fingerprint']::text[]
    OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute WHERE attrelid=receipt AND attnum>0 AND NOT attisdropped)
      IS DISTINCT FROM ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'text'::regtype]::oid[]
    OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=receipt AND attnum>0 AND NOT attisdropped AND NOT attnotnull)
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=receipt AND contype='p' AND conkey=ARRAY[1,2]::smallint[]
      AND NOT condeferrable AND convalidated)
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=receipt AND contype='u' AND conkey=ARRAY[3]::smallint[]
      AND NOT condeferrable AND convalidated)
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=receipt AND contype='c' AND convalidated
      AND position('resolution_fingerprint ~ ''^[0-9a-f]{64}$''' IN pg_get_constraintdef(oid))>0)
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid=receipt AND NOT tgisinternal)<>1
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=receipt AND NOT tgisinternal AND tgtype=27 AND tgenabled='O'
      AND tgfoid='app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure)
  THEN RAISE EXCEPTION '0142 common receipt must remain immutable, private and typed metadata only'; END IF;
  IF EXISTS(
    WITH expected(name,source_keys,parent,target_keys,deferred) AS (VALUES
      ('pmmr_generation_fk',ARRAY[3],'app_private.personal_target_merge_generations_v1',ARRAY[1],false),
      ('pmmr_contact_request_fk',ARRAY[1,2],'app_private.personal_merge_contact_resolution_requests_v1',ARRAY[1,2],true),
      ('pmmr_project_request_fk',ARRAY[1,2],'app_private.personal_merge_project_relationship_resolution_requests_v1',ARRAY[1,2],true)
    ) SELECT 1 FROM expected e LEFT JOIN pg_constraint c ON c.conrelid=receipt AND c.conname=e.name AND c.contype='f'
      AND c.conkey=e.source_keys::smallint[] AND c.confrelid=to_regclass(e.parent) AND c.confkey=e.target_keys::smallint[]
      AND c.confdeltype='r' AND c.confupdtype='a' AND c.convalidated AND c.condeferrable=e.deferred AND c.condeferred=e.deferred
    WHERE c.oid IS NULL
  ) OR (SELECT count(*) FROM pg_constraint WHERE conrelid=receipt AND contype='f')<>3
  THEN RAISE EXCEPTION '0142 exact generation and deferred family receipt foreign keys drift'; END IF;
  IF (SELECT count(*) FROM regexp_matches((SELECT prosrc FROM pg_proc
      WHERE oid='app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure),
      'apply_personal_merge_contact_resolutions_v1\s*\(','g'))<>1
    OR (SELECT count(*) FROM regexp_matches((SELECT prosrc FROM pg_proc
      WHERE oid='app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure),
      'apply_personal_merge_project_relationship_resolutions_v1\s*\(','g'))<>1
    OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid)'::regprocedure
      AND position('personal_merge_unassigned_contact_requests_v1' IN prosrc)>0
      AND position('personal_merge_unassigned_contact_purges_v1' IN prosrc)>0
      AND position('personal_merge_project_relationship_resolution_fact_proof_v1' IN prosrc)>0)
    OR (SELECT count(*) FROM regexp_matches((SELECT prosrc FROM pg_proc
      WHERE oid='app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure),
      'personal_merge_mixed_resolution_proof_v1\s*\(','g'))<>1
  THEN RAISE EXCEPTION '0142 shared applications, old single-family refusal or narrow mixed end proof is missing'; END IF;
END $check$;
