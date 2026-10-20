\set ON_ERROR_STOP on
DO $check$
DECLARE
  confirmer regprocedure := 'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  proof regprocedure := 'app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid)'::regprocedure;
  trusted_owner oid; candidate regprocedure; relation regclass;
  columns text[]; types oid[]; nullable text[]; primary_columns smallint[];
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0138_personal_merge_project_relationship_resolution_confirmation') <> 1
  THEN RAISE EXCEPTION '0138 project relationship confirmation migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF has_schema_privilege('public','app_private','USAGE') OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
  THEN RAISE EXCEPTION '0138 private schema cannot be opened'; END IF;
  FOREACH candidate IN ARRAY ARRAY[confirmer,proof] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=candidate AND proowner=trusted_owner AND prosecdef
        AND proconfig=ARRAY['search_path=pg_catalog']::text[] AND NOT proretset
        AND provolatile=CASE WHEN candidate=proof THEN 's'::"char" ELSE 'v'::"char" END
        AND prorettype=CASE WHEN candidate=proof THEN 'boolean'::regtype ELSE 'timestamptz'::regtype END)
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
        WHERE p.oid=candidate AND acl.grantee<>p.proowner)
    THEN RAISE EXCEPTION '0138 function result, owner, security or ACL drift: %',candidate; END IF;
  END LOOP;
  FOREACH candidate IN ARRAY ARRAY[
    'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure,
    'app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=candidate AND proowner=trusted_owner AND prosecdef
        AND provolatile='v' AND prorettype='trigger'::regtype AND proconfig=ARRAY['search_path=pg_catalog']::text[])
      OR has_function_privilege('public',candidate,'EXECUTE') OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
    THEN RAISE EXCEPTION '0138 existing guard security or owner drift: %',candidate; END IF;
  END LOOP;
  IF (SELECT count(*) FROM regexp_matches((SELECT prosrc FROM pg_proc
        WHERE oid='app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure),
      'personal_merge_project_relationship_resolution_proof_v1\s*\(','g'))<>1
    OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure
      AND position('FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge' IN prosrc)>0
      AND position('FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application' IN prosrc)>0
      AND position('pending project relationship deletion requires expiry or applied confirmation receipt' IN prosrc)>0)
  THEN RAISE EXCEPTION '0138 end proof or additive payload expiry/confirmation paths are missing'; END IF;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_merge_project_relationship_resolution_requests_v1'::regclass,
    'app_private.personal_merge_project_relationship_history_applications_v1'::regclass,
    'app_private.personal_merge_project_relationship_current_choices_v1'::regclass] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid=relation AND relkind='r' AND relowner=trusted_owner)
      OR has_table_privilege('public',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
        WHERE c.oid=relation AND acl.grantee<>c.relowner)
    THEN RAISE EXCEPTION '0138 immutable metadata owner or ACL drift: %',relation; END IF;
    CASE relation
      WHEN 'app_private.personal_merge_project_relationship_resolution_requests_v1'::regclass THEN
        columns:=ARRAY['actor_app_user_id','request_id','workspace_id','project_id','generation_id','known_fact_fingerprint',
          'pending_fingerprint','resolution_fingerprint','post_known_fact_fingerprint','confirmed_at_utc'];
        types:=ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,
          'text'::regtype,'text'::regtype,'text'::regtype,'text'::regtype,'timestamptz'::regtype];
        nullable:=ARRAY[]::text[]; primary_columns:=ARRAY[1,2]::smallint[];
      WHEN 'app_private.personal_merge_project_relationship_history_applications_v1'::regclass THEN
        columns:=ARRAY['pending_fact_id','actor_app_user_id','request_id','source_target_id','project_id','original_revision_number','applied_revision_number'];
        types:=ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'int4'::regtype,'int4'::regtype];
        nullable:=ARRAY[]::text[]; primary_columns:=ARRAY[1]::smallint[];
      ELSE
        columns:=ARRAY['actor_app_user_id','request_id','project_id','source_target_id','original_revision_number',
          'final_revision_number','original_merge_generation_id','selected_pending_fact_id'];
        types:=ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'int4'::regtype,'int4'::regtype,'uuid'::regtype,'uuid'::regtype];
        nullable:=ARRAY['original_merge_generation_id','selected_pending_fact_id']; primary_columns:=ARRAY[1,2,3,4]::smallint[];
    END CASE;
    IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM columns
      OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM types
      OR (SELECT coalesce(array_agg(attname::text ORDER BY attnum),ARRAY[]::text[]) FROM pg_attribute
        WHERE attrelid=relation AND attnum>0 AND NOT attisdropped AND NOT attnotnull) IS DISTINCT FROM nullable
      OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=relation AND contype='p' AND conkey=primary_columns
        AND NOT condeferrable AND convalidated)
      OR (SELECT count(*) FROM pg_trigger WHERE tgrelid=relation AND NOT tgisinternal)<>1
      OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=relation AND NOT tgisinternal AND tgtype=27 AND tgenabled='O'
        AND tgfoid='app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure)
    THEN RAISE EXCEPTION '0138 typed metadata, primary key or immutable trigger drift: %',relation; END IF;
  END LOOP;
  IF EXISTS (
    WITH expected(name,child,source_keys,parent,target_keys,deferred) AS (VALUES
      ('pmprr_request_actor_fk','personal_merge_project_relationship_resolution_requests_v1',ARRAY[1],'app_data.app_users',ARRAY[1],false),
      ('pmprr_request_workspace_fk','personal_merge_project_relationship_resolution_requests_v1',ARRAY[3],'app_data.workspaces',ARRAY[1],false),
      ('pmprr_request_project_fk','personal_merge_project_relationship_resolution_requests_v1',ARRAY[4],'app_data.projects',ARRAY[1],false),
      ('pmprr_request_generation_fk','personal_merge_project_relationship_resolution_requests_v1',ARRAY[5],'app_private.personal_target_merge_generations_v1',ARRAY[1],false),
      ('pmprr_request_end_fk','personal_merge_project_relationship_resolution_requests_v1',ARRAY[1,2],'app_private.personal_target_merge_end_events_v1',ARRAY[2,5],true),
      ('pmprr_history_pending_fk','personal_merge_project_relationship_history_applications_v1',ARRAY[1],'app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[1],false),
      ('pmprr_history_request_fk','personal_merge_project_relationship_history_applications_v1',ARRAY[2,3],'app_private.personal_merge_project_relationship_resolution_requests_v1',ARRAY[1,2],true),
      ('pmprr_history_base_fk','personal_merge_project_relationship_history_applications_v1',ARRAY[4,5,6],'app_data.promotion_target_relationship_revisions',ARRAY[1,2,3],false),
      ('pmprr_history_applied_fk','personal_merge_project_relationship_history_applications_v1',ARRAY[4,5,7],'app_data.promotion_target_relationship_revisions',ARRAY[1,2,3],false),
      ('pmprr_current_request_fk','personal_merge_project_relationship_current_choices_v1',ARRAY[1,2],'app_private.personal_merge_project_relationship_resolution_requests_v1',ARRAY[1,2],true),
      ('pmprr_current_base_fk','personal_merge_project_relationship_current_choices_v1',ARRAY[4,3,5],'app_data.promotion_target_relationship_revisions',ARRAY[1,2,3],false),
      ('pmprr_current_final_fk','personal_merge_project_relationship_current_choices_v1',ARRAY[4,3,6],'app_data.promotion_target_relationship_revisions',ARRAY[1,2,3],false),
      ('pmprr_current_selected_fk','personal_merge_project_relationship_current_choices_v1',ARRAY[8],'app_private.personal_merge_project_relationship_history_applications_v1',ARRAY[1],false),
      ('pmprr_current_binding_fk','personal_merge_project_relationship_current_choices_v1',ARRAY[7,4],'app_private.personal_target_merge_generation_members_v1',ARRAY[1,4],false)
    ) SELECT 1 FROM expected e LEFT JOIN pg_constraint c ON c.conname=e.name AND c.conrelid=to_regclass('app_private.'||e.child)
      AND c.contype='f' AND c.conkey=e.source_keys::smallint[] AND c.confrelid=to_regclass(e.parent)
      AND c.confkey=e.target_keys::smallint[] AND c.confdeltype='r' AND c.confupdtype='a'
      AND c.condeferrable=e.deferred AND c.condeferred=e.deferred AND c.convalidated WHERE c.oid IS NULL
  ) OR (SELECT count(*) FROM pg_constraint WHERE contype='f' AND conrelid IN (
    'app_private.personal_merge_project_relationship_resolution_requests_v1'::regclass,
    'app_private.personal_merge_project_relationship_history_applications_v1'::regclass,
    'app_private.personal_merge_project_relationship_current_choices_v1'::regclass))<>14
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='app_private.personal_merge_project_relationship_resolution_requests_v1'::regclass
      AND contype='u' AND conkey=ARRAY[5]::smallint[] AND NOT condeferrable AND convalidated)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='app_private.personal_merge_project_relationship_history_applications_v1'::regclass
      AND contype='u' AND conkey=ARRAY[4,5,7]::smallint[] AND NOT condeferrable AND convalidated)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='app_private.personal_merge_project_relationship_current_choices_v1'::regclass
      AND contype='u' AND conkey=ARRAY[4,3,6]::smallint[] AND NOT condeferrable AND convalidated)
  THEN RAISE EXCEPTION '0138 exact foreign keys, deferred end/request links or generation/application uniqueness drift'; END IF;
END
$check$;
