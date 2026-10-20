\set ON_ERROR_STOP on
DO $check$
DECLARE
  confirmer regprocedure:='app_private.confirm_personal_merge_project_relationship_resolutions_v2(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb,jsonb)'::regprocedure;
  proof regprocedure:='app_private.personal_merge_project_entry_resolution_proof_v1(uuid,uuid)'::regprocedure;
  trusted_owner oid; candidate regprocedure; relation regclass;
  columns text[]; types oid[]; primary_columns smallint[];
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
    WHERE version='0140_explicit_project_entry_relationship_resolution')<>1
  THEN RAISE EXCEPTION '0140 explicit project entry migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid='app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  IF has_schema_privilege('public','app_private','USAGE') OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
  THEN RAISE EXCEPTION '0140 private schema cannot be opened'; END IF;
  FOREACH candidate IN ARRAY ARRAY[confirmer,proof] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=candidate AND proowner=trusted_owner AND prosecdef
      AND proconfig=ARRAY['search_path=pg_catalog']::text[] AND NOT proretset
      AND provolatile=CASE WHEN candidate=proof THEN 's'::"char" ELSE 'v'::"char" END
      AND prorettype=CASE WHEN candidate=proof THEN 'boolean'::regtype ELSE 'timestamptz'::regtype END)
      OR has_function_privilege('public',candidate,'EXECUTE') OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
        WHERE p.oid=candidate AND acl.grantee<>p.proowner)
    THEN RAISE EXCEPTION '0140 function identity, owner, security or ACL drift: %',candidate; END IF;
  END LOOP;
  FOREACH relation IN ARRAY ARRAY['app_private.personal_merge_project_entry_resolution_requests_v1'::regclass,
    'app_private.personal_merge_project_entry_origins_v1'::regclass] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=relation AND relkind='r' AND relowner=trusted_owner)
      OR has_table_privilege('public',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
        WHERE c.oid=relation AND acl.grantee<>c.relowner)
    THEN RAISE EXCEPTION '0140 metadata owner or ACL drift: %',relation; END IF;
    IF relation='app_private.personal_merge_project_entry_resolution_requests_v1'::regclass THEN
      columns:=ARRAY['actor_app_user_id','request_id','workspace_id','project_id','generation_id','known_fact_fingerprint',
        'pending_fingerprint','resolution_fingerprint','internal_known_fact_fingerprint','internal_resolution_fingerprint','initialized_at_utc'];
      types:=ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,
        'text'::regtype,'text'::regtype,'text'::regtype,'text'::regtype,'text'::regtype,'timestamptz'::regtype];
      primary_columns:=ARRAY[1,2]::smallint[];
    ELSE
      columns:=ARRAY['actor_app_user_id','request_id','project_id','source_target_id','pending_fact_id','initial_revision_number','initialized_at_utc'];
      types:=ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'int4'::regtype,'timestamptz'::regtype];
      primary_columns:=ARRAY[1,2,3,4]::smallint[];
    END IF;
    IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM columns
      OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM types
      OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped AND NOT attnotnull)
      OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=relation AND contype='p' AND conkey=primary_columns
        AND NOT condeferrable AND convalidated)
      OR (SELECT count(*) FROM pg_trigger WHERE tgrelid=relation AND NOT tgisinternal)<>1
      OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=relation AND NOT tgisinternal AND tgtype=27 AND tgenabled='O'
        AND tgfoid='app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure)
      OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=relation AND contype='c' AND convalidated
        AND position('isfinite(initialized_at_utc)' IN pg_get_constraintdef(oid))>0)
    THEN RAISE EXCEPTION '0140 value-free typed metadata, keys, finite time or immutable trigger drift: %',relation; END IF;
  END LOOP;
  IF EXISTS(
    WITH expected(name,child,source_keys,parent,target_keys,deferred) AS (VALUES
      ('pmer_request_actor_fk','personal_merge_project_entry_resolution_requests_v1',ARRAY[1],'app_data.app_users',ARRAY[1],false),
      ('pmer_request_workspace_fk','personal_merge_project_entry_resolution_requests_v1',ARRAY[3],'app_data.workspaces',ARRAY[1],false),
      ('pmer_request_project_fk','personal_merge_project_entry_resolution_requests_v1',ARRAY[4],'app_data.projects',ARRAY[1],false),
      ('pmer_request_generation_fk','personal_merge_project_entry_resolution_requests_v1',ARRAY[5],'app_private.personal_target_merge_generations_v1',ARRAY[1],false),
      ('pmer_request_inner_fk','personal_merge_project_entry_resolution_requests_v1',ARRAY[1,2],'app_private.personal_merge_project_relationship_resolution_requests_v1',ARRAY[1,2],true),
      ('pmer_origin_request_fk','personal_merge_project_entry_origins_v1',ARRAY[1,2],'app_private.personal_merge_project_entry_resolution_requests_v1',ARRAY[1,2],false),
      ('pmer_origin_pending_fk','personal_merge_project_entry_origins_v1',ARRAY[5],'app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[1],false),
      ('pmer_origin_initial_fk','personal_merge_project_entry_origins_v1',ARRAY[4,3,6],'app_data.promotion_target_relationship_revisions',ARRAY[1,2,3],false)
    ) SELECT 1 FROM expected e LEFT JOIN pg_constraint c ON c.conname=e.name AND c.conrelid=to_regclass('app_private.'||e.child)
      AND c.contype='f' AND c.conkey=e.source_keys::smallint[] AND c.confrelid=to_regclass(e.parent)
      AND c.confkey=e.target_keys::smallint[] AND c.confdeltype='r' AND c.confupdtype='a'
      AND c.condeferrable=e.deferred AND c.condeferred=e.deferred AND c.convalidated WHERE c.oid IS NULL
  ) OR (SELECT count(*) FROM pg_constraint WHERE contype='f' AND conrelid IN (
      'app_private.personal_merge_project_entry_resolution_requests_v1'::regclass,'app_private.personal_merge_project_entry_origins_v1'::regclass))<>8
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app_private.personal_merge_project_entry_resolution_requests_v1'::regclass
      AND contype='u' AND conkey=ARRAY[5]::smallint[] AND NOT condeferrable AND convalidated)
    OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app_private.personal_merge_project_entry_origins_v1'::regclass
      AND contype='c' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((initial_revision_number = 1))')
  THEN RAISE EXCEPTION '0140 exact foreign keys, deferred inner request or real initial revision drift'; END IF;
END $check$;
