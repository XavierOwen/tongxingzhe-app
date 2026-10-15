\set ON_ERROR_STOP on
DO $check$
DECLARE
  projection_function regprocedure :=
    'app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  reader_function regprocedure :=
    'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  body text;
  executable_body text;
  command_body text;
  required_fragment text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0122_personal_target_authorized_known_source_merge_projection') <> 1
    OR NOT EXISTS (
      SELECT 1 FROM pg_proc AS reader
      JOIN pg_proc AS projection ON projection.oid = projection_function
      WHERE reader.oid = reader_function AND reader.proowner = projection.proowner
        AND reader.prosecdef AND reader.provolatile = 'v'
        AND reader.proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[]
        AND reader.proargnames = ARRAY[
          'trusted_issuer','trusted_subject','trusted_project_id','requested_generation_id'
        ]::text[]
        AND reader.prorettype = 'jsonb'::regtype
        AND NOT reader.proretset AND reader.prokind = 'f'
    )
    OR has_function_privilege('public', reader_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', reader_function, 'EXECUTE')
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = projection_function
      AND provolatile = 's' AND prosecdef)
  THEN RAISE EXCEPTION '0122 authorized projection migration or function contract drift'; END IF;

  SELECT lower(regexp_replace(prosrc, '--[^\n]*', '', 'g')) INTO body
  FROM pg_proc WHERE oid = reader_function;
  body := regexp_replace(body, '\s+', ' ', 'g');
  executable_body := regexp_replace(body, '''(''''|[^''])*''', '''''', 'g');
  command_body := substring(executable_body FROM 'with context as materialized \(.*?;');
  IF command_body IS NULL
    OR replace(executable_body, command_body, '') ~ '\m(select|with|insert)\M'
    OR executable_body ~ '\m(perform|execute|call|update|delete|merge|truncate|create|alter|drop|grant)\M'
    OR executable_body ~ 'for (update|share)|pg_advisory|bootstrap|list_personal_project_contexts|fence|expiry'
    OR (SELECT count(*) FROM regexp_matches(executable_body, '\mwith\M', 'g')) <> 1
    OR (SELECT count(*) FROM regexp_matches(executable_body, '\minsert\M', 'g')) <> 1
    OR (SELECT count(*) FROM regexp_matches(executable_body,
      'app_private\.read_known_source_personal_target_merge_projection_v1\s*\(', 'g')) <> 1
    OR regexp_replace(regexp_replace(executable_body,
      'app_private\.read_known_source_personal_target_merge_projection_v1\s*\(', '', 'g'),
      'insert into app_data\.promotion_target_access_events\s*\(', '', 'g')
      ~ 'app_(data|private)\.[a-z0-9_]+\s*\('
  THEN RAISE EXCEPTION '0122 reader must use one projection command and only source-view audit writes'; END IF;

  FOREACH required_fragment IN ARRAY ARRAY[
    'trusted_issuer is null or btrim(trusted_issuer) = ''''',
    'char_length(trusted_issuer) > 2048',
    'trusted_subject is null or btrim(trusted_subject) = ''''',
    'char_length(trusted_subject) > 512',
    'trusted_project_id is null or requested_generation_id is null',
    'identity_row.issuer = trusted_issuer',
    'identity_row.subject = trusted_subject',
    'actor.status = ''active''',
    'workspace_row.personal_owner_app_user_id = actor.app_user_id',
    'workspace_row.workspace_kind = ''personal''',
    'workspace_row.deleted_at is null',
    'current_project.app_user_id = actor.app_user_id',
    'current_project.project_id = trusted_project_id',
    'project_row.workspace_id = workspace_row.workspace_id',
    'project_row.status = ''active''',
    'projected as materialized',
    'context.app_user_id, context.workspace_id, trusted_project_id, requested_generation_id',
    'insert into app_data.promotion_target_access_events',
    'jsonb_array_elements(projected.document -> ''sources'')',
    '(source.document ->> ''target_id'')::uuid',
    '''viewed'', statement_timestamp()',
    'select projected.document, access_count.inserted_count',
    'select count(*) as inserted_count from inserted_access_events',
    'into projection, inserted_count',
    'if not found then',
    'if inserted_count <> 2 then',
    'errcode = ''22023''',
    'errcode = ''42501''',
    'errcode = ''55000''',
    'return projection;'
  ] LOOP
    IF strpos(body, required_fragment) = 0 THEN
      RAISE EXCEPTION '0122 authorized projection requirement missing: %', required_fragment;
    END IF;
  END LOOP;
  IF command_body !~ 'projected as materialized .*inserted_access_events as .*insert into app_data\.promotion_target_access_events .*select projected\.document, access_count\.inserted_count .*into projection, inserted_count .*from projected cross join \(select count\(\*\) as inserted_count from inserted_access_events\) as access_count;'
  THEN RAISE EXCEPTION '0122 projection result and audit count must consume the same command'; END IF;
END
$check$;
