\set ON_ERROR_STOP on
DO $check$
DECLARE
  catalog_function regprocedure :=
    'app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)'::regprocedure;
  manifest_function regprocedure :=
    'app_private.personal_target_merge_known_source_manifest_v1(uuid)'::regprocedure;
  reader_function regprocedure :=
    'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  trusted_owner oid;
  candidate regprocedure;
  body text;
  code text;
  command_body text;
  fragment text;
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0124_personal_target_merge_split_plan') <> 1
  THEN RAISE EXCEPTION '0124 split plan migration is missing'; END IF;

  FOREACH candidate IN ARRAY ARRAY[catalog_function,manifest_function,reader_function] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate
        AND proowner = trusted_owner AND prosecdef AND provolatile = 's'
        AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
    THEN RAISE EXCEPTION '0124 helper or reader owner, security, volatility or ACL drift: %',candidate; END IF;
    SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO body FROM pg_proc WHERE oid = candidate;
    code := regexp_replace(body,'''(''''|[^''])*''','''''','g');
    IF code ~ '\m(insert|update|delete|perform|execute|call|truncate|create|alter|drop|grant)\M'
      OR code ~ 'for (update|share)|pg_advisory|acquire_personal_target_merge_generation_fence|bootstrap|list_personal_project_contexts|expire_known_source'
    THEN RAISE EXCEPTION '0124 split plan and catalog must be read-only and take no locks'; END IF;
  END LOOP;
  IF pg_get_function_result(catalog_function) <> 'TABLE(source_target_id uuid, metadata jsonb)'
    OR (SELECT proargnames FROM pg_proc WHERE oid = catalog_function) IS DISTINCT FROM
      ARRAY['requested_generation_id','source_target_id','metadata']::text[]
    OR pg_get_function_result(manifest_function) <> 'TABLE(fact_count bigint, fact_fingerprint text)'
    OR (SELECT proargnames FROM pg_proc WHERE oid = manifest_function) IS DISTINCT FROM
      ARRAY['requested_generation_id','fact_count','fact_fingerprint']::text[]
    OR pg_get_function_result(reader_function) <> 'jsonb'
    OR (SELECT proargnames FROM pg_proc WHERE oid = reader_function) IS DISTINCT FROM
      ARRAY['trusted_app_user_id','trusted_workspace_id','trusted_project_id','requested_generation_id']::text[]
  THEN RAISE EXCEPTION '0124 catalog, manifest or split-plan signature drift'; END IF;

  SELECT lower(regexp_replace(prosrc,'\s+',' ','g')) INTO body FROM pg_proc WHERE oid = catalog_function;
  IF (SELECT count(*) FROM regexp_matches(body,'jsonb_build_array\(','g')) <> 7
    OR (SELECT count(*) FROM regexp_matches(body,'\munion all\M','g')) <> 6
    OR body ~ 'app_data\.contacts|display_name|\.phone|\.email|follow_up_note|response_level|follow_up_consent|reason_detail|occurred_at'
  THEN RAISE EXCEPTION '0124 fact catalog must retain seven metadata variants without business values'; END IF;
  FOREACH fragment IN ARRAY ARRAY[
    'app_data.contact_target_links','app_data.promotion_target_project_relationships',
    'app_data.promotion_target_relationship_revisions','app_data.promotion_target_institution_relationships',
    'app_data.promotion_target_institution_relation_revisions',
    '''contact_link''','''project_relationship''','''project_revision''',
    '''institution_relationship_person''','''institution_relationship_institution''',
    '''institution_revision_person''','''institution_revision_institution''',
    'link.merge_generation_id = requested_generation_id',
    'relation.merge_generation_id = requested_generation_id',
    'revision.merge_generation_id = requested_generation_id',
    'relation.person_merge_generation_id = requested_generation_id',
    'relation.institution_merge_generation_id = requested_generation_id',
    'revision.person_merge_generation_id = requested_generation_id',
    'revision.institution_merge_generation_id = requested_generation_id'
  ] LOOP
    IF strpos(body,fragment) = 0 THEN RAISE EXCEPTION '0124 fact catalog source or variant missing: %',fragment; END IF;
  END LOOP;

  SELECT lower(regexp_replace(prosrc,'\s+',' ','g')) INTO body FROM pg_proc WHERE oid = manifest_function;
  FOREACH fragment IN ARRAY ARRAY[
    'from app_private.personal_target_merge_known_source_fact_catalog_v1(requested_generation_id)',
    'select count(*), encode(sha256(convert_to(',
    '''contract'', ''personal_target_merge_known_source_manifest_v1''',
    '''generation_id'', requested_generation_id',
    '''facts'', coalesce(jsonb_agg(metadata order by metadata::text), ''[]''::jsonb)',
    ')::text, ''utf8'' )), ''hex'')',
    'having coalesce(bool_and(exists (',
    'member.generation_id = requested_generation_id',
    'member.promotion_target_id = facts.source_target_id'
  ] LOOP
    IF strpos(body,fragment) = 0 THEN RAISE EXCEPTION '0124 manifest delegation or original fingerprint contract drift: %',fragment; END IF;
  END LOOP;

  SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO body FROM pg_proc WHERE oid = reader_function;
  body := regexp_replace(body,'\s+',' ','g');
  code := regexp_replace(body,'''(''''|[^''])*''','''''','g');
  command_body := substring(code FROM 'with context as materialized \(.*?;');
  IF command_body IS NULL OR replace(code,command_body,'') ~ '\m(select|with)\M'
    OR body ~ 'activation_requests|field_choice|retained_target|display_name|\.phone|\.email|follow_up_note|response_level|follow_up_consent|promotion_target_document|promotion_target_access_events'
  THEN RAISE EXCEPTION '0124 split plan must use one snapshot, accept v1 and return only metadata'; END IF;
  FOREACH fragment IN ARRAY ARRAY[
    'trusted_app_user_id is null or trusted_workspace_id is null',
    'trusted_project_id is null or requested_generation_id is null',
    'workspace_row.workspace_id = trusted_workspace_id',
    'workspace_row.workspace_kind = ''personal''',
    'workspace_row.personal_owner_app_user_id = trusted_app_user_id',
    'workspace_row.deleted_at is null','actor.status = ''active''',
    'current_project.app_user_id = trusted_app_user_id',
    'current_project.project_id = project_row.project_id',
    'project_row.project_id = trusted_project_id','project_row.status = ''active''',
    'generation_row.created_by_app_user_id = trusted_app_user_id',
    'members.member_count <> 2','active_members.member_count <> 2',
    'member.workspace_id = generation.workspace_id','member.target_type = generation.target_type',
    'active_members.target_ids is distinct from members.target_ids',
    'target.status = ''active''','assignment.app_user_id = trusted_app_user_id',
    'assignment.ended_at is null','source.review_due_at > statement_timestamp()',
    'app_private.personal_target_merge_end_events_v1',
    'app_private.personal_target_merge_known_source_fact_catalog_v1(',
    'app_private.personal_target_merge_known_source_manifest_v1(',
    'facts.source_target_id = any(members.target_ids)',
    'order by member.promotion_target_id','order by facts.metadata::text',
    '''generation_id''','''workspace_id''','''project_id''','''target_type''',
    '''member_target_ids''','''review_due_at_utc''','''fact_count''','''fact_fingerprint''','''facts''',
    '''source_target_id'', facts.source_target_id, ''metadata'', facts.metadata',
    'errcode = ''22023''','errcode = ''42501''','errcode = ''55000''','return split_plan;'
  ] LOOP
    IF strpos(body,fragment) = 0 THEN RAISE EXCEPTION '0124 split-plan gate or output requirement missing: %',fragment; END IF;
  END LOOP;
END
$check$;
