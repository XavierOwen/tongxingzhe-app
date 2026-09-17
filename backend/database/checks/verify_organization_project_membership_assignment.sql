\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  object_id oid;
  bridge regprocedure := 'app_data.assign_organization_project_member_for_identity_v1(text,text,uuid,uuid,uuid,uuid)'::regprocedure;
  writer regprocedure := 'app_private.assign_organization_project_member_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  claim_table regclass := 'app_private.organization_project_membership_assignment_request_claims'::regclass;
  tombstone_table regclass := 'app_private.organization_project_membership_assignment_request_tombstones'::regclass;
  audit_table regclass := 'app_private.organization_project_membership_assignment_audit_events'::regclass;
  names text[]; types text[]; nullable boolean[]; definition text;
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF pg_get_userbyid(trusted_owner) = 'tongxingzhe_runtime'
    OR (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0096_organization_project_membership_assignment') <> 1 THEN
    RAISE EXCEPTION '0096 migration or trusted owner drift';
  END IF;
  FOREACH object_id IN ARRAY ARRAY[claim_table::oid,tombstone_table::oid,audit_table::oid] LOOP
    IF (SELECT relowner FROM pg_class WHERE oid = object_id) IS DISTINCT FROM trusted_owner
      OR has_table_privilege('tongxingzhe_runtime',object_id,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class AS c CROSS JOIN LATERAL
        aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) AS a
        WHERE c.oid = object_id AND a.grantee = 0)
      OR NOT EXISTS (SELECT 1 FROM pg_trigger
        WHERE tgrelid = object_id AND tgtype = 27 AND tgenabled = 'O' AND NOT tgisinternal)
    THEN RAISE EXCEPTION '0096 private table boundary drift: %',object_id::regclass; END IF;
  END LOOP;
  SELECT array_agg(attname::text ORDER BY attnum),
    array_agg(format_type(atttypid,atttypmod) ORDER BY attnum),
    array_agg(NOT attnotnull ORDER BY attnum) INTO names,types,nullable
  FROM pg_attribute WHERE attrelid = claim_table AND attnum > 0 AND NOT attisdropped;
  IF names IS DISTINCT FROM ARRAY['request_id','actor_app_user_id','organization_workspace_id','project_id',
      'organization_membership_id','project_membership_id','active_from_utc','inactive_from_utc']::text[]
    OR types IS DISTINCT FROM ARRAY['uuid','uuid','uuid','uuid','uuid','uuid','timestamp with time zone','timestamp with time zone']::text[]
    OR nullable IS DISTINCT FROM ARRAY[false,true,false,false,false,false,false,true]
    OR (SELECT count(*) FROM pg_constraint WHERE conrelid = claim_table AND contype = 'f') <> 1
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = claim_table AND contype = 'f'
      AND confrelid = 'app_data.app_users'::regclass AND conkey = ARRAY[2]::smallint[] AND confdeltype = 'n')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = claim_table AND contype = 'p'
      AND conkey = ARRAY[1]::smallint[]) THEN RAISE EXCEPTION '0096 claim shape drift'; END IF;
  SELECT array_agg(attname::text ORDER BY attnum) INTO names FROM pg_attribute
  WHERE attrelid = tombstone_table AND attnum > 0 AND NOT attisdropped;
  IF names IS DISTINCT FROM ARRAY['claim_family','request_id']::text[]
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = tombstone_table AND contype = 'p'
      AND conkey = ARRAY[1,2]::smallint[])
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = tombstone_table AND contype = 'c'
      AND pg_get_constraintdef(oid) = 'CHECK ((claim_family = ''organization-project-membership-assignment:v1''::text))')
    THEN RAISE EXCEPTION '0096 tombstone shape drift'; END IF;
  SELECT array_agg(attname::text ORDER BY attnum) INTO names FROM pg_attribute
  WHERE attrelid = audit_table AND attnum > 0 AND NOT attisdropped;
  IF names IS DISTINCT FROM ARRAY['project_membership_assignment_audit_event_id',
    'project_membership_assignment_contract_id','request_id','organization_workspace_id','project_id',
    'project_membership_id','active_from_utc','inactive_from_utc']::text[]
    OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid IN (tombstone_table,audit_table) AND contype = 'f')
    THEN RAISE EXCEPTION '0096 audit lineage drift'; END IF;
  FOREACH object_id IN ARRAY ARRAY[writer::oid,bridge::oid,
    'app_private.protect_organization_project_membership_assignment_claim_v1()'::regprocedure::oid,
    'app_private.protect_organization_project_membership_assignment_terminal_v1()'::regprocedure::oid] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = object_id AND proowner = trusted_owner
      AND prosecdef AND provolatile = 'v' AND proconfig = ARRAY['search_path=pg_catalog']::text[])
      OR EXISTS (SELECT 1 FROM pg_proc AS p CROSS JOIN LATERAL
        aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) AS a
        WHERE p.oid = object_id AND a.grantee = 0)
      OR has_function_privilege('tongxingzhe_runtime',object_id,'EXECUTE') IS DISTINCT FROM (object_id = bridge::oid)
      THEN RAISE EXCEPTION '0096 function security drift: %',object_id::regprocedure; END IF;
  END LOOP;
  FOREACH object_id IN ARRAY ARRAY[writer::oid,bridge::oid] LOOP
    SELECT proargnames[array_length(proargnames,1)-6:array_length(proargnames,1)]
      INTO names FROM pg_proc WHERE oid = object_id;
    IF names IS DISTINCT FROM ARRAY['project_membership_assignment_contract_id','organization_workspace_id',
      'project_id','organization_membership_id','project_membership_id','active_from_utc','inactive_from_utc']::text[]
      OR pg_get_function_result(object_id) <> 'TABLE(project_membership_assignment_contract_id text, organization_workspace_id uuid, project_id uuid, organization_membership_id uuid, project_membership_id uuid, active_from_utc timestamp with time zone, inactive_from_utc timestamp with time zone)'
      THEN RAISE EXCEPTION '0096 exact typed receipt drift'; END IF;
    definition := pg_get_functiondef(object_id);
    IF strpos(definition,'current_setting(''transaction_isolation'')') = 0
      OR strpos(definition,'requires read committed') = 0
      OR strpos(definition,'current_setting(''transaction_isolation'')') > strpos(definition,'FROM app_')
      THEN RAISE EXCEPTION '0096 isolation guard must precede facts'; END IF;
  END LOOP;
  definition := pg_get_functiondef(writer);
  IF strpos(definition,'organization-project-membership-assignment-request:')
      >= strpos(definition,'organization_project_membership_assignment_request_tombstones AS tombstone')
    OR strpos(definition,'organization_project_membership_assignment_request_tombstones AS tombstone')
      >= strpos(definition,'organization_project_membership_assignment_request_claims AS claim')
    OR strpos(definition,'ORDER BY user_id') = 0
    OR strpos(definition,'lock_organization_governance_v1') >= strpos(definition,'''organization-membership:''')
    OR strpos(definition,'''organization-membership:''') >= strpos(definition,'''project-membership:''')
    OR strpos(definition,'''project-membership:''') >= strpos(definition,'''management-follow-up-consent-opt-in:''')
    OR strpos(definition,'''management-follow-up-consent-opt-in:''') >= strpos(definition,'assignment_time := clock_timestamp()')
    OR (length(definition)-length(replace(definition,'clock_timestamp()',''))) / length('clock_timestamp()') <> 1
    OR definition ~ 'FROM app_data.projects[^;]*FOR (UPDATE|SHARE)'
    OR definition LIKE '%INSERT INTO app_data.management_report_capability_grants%'
    THEN RAISE EXCEPTION '0096 lock/time/default-promoter contract drift'; END IF;
END
$check$;
