\set ON_ERROR_STOP on
DO $check$
DECLARE
  reader regprocedure := 'app_data.list_org_join_applications_for_identity_v1(text,text,uuid)'::regprocedure;
  trusted_owner oid;
  runtime_role oid := 'tongxingzhe_runtime'::regrole;
  input_names text[]; output_names text[]; output_types text[];
  definition text := pg_get_functiondef(reader);
  relation regclass;
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF trusted_owner = runtime_role OR NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE oid = reader AND proowner = trusted_owner
      AND prosecdef AND proretset AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog']::text[]
  ) THEN RAISE EXCEPTION '0099 directory function security boundary drift'; END IF;
  SELECT p.proargnames[1:3],
    array_agg(a.name ORDER BY a.ordinality) FILTER (WHERE a.mode = 't'),
    array_agg(format_type(a.type, NULL) ORDER BY a.ordinality) FILTER (WHERE a.mode = 't')
  INTO input_names, output_names, output_types
  FROM pg_proc p CROSS JOIN LATERAL unnest(p.proallargtypes, p.proargmodes, p.proargnames)
    WITH ORDINALITY AS a(type, mode, name, ordinality)
  WHERE p.oid = reader GROUP BY p.proargnames;
  IF input_names IS DISTINCT FROM ARRAY['trusted_issuer', 'trusted_subject', 'requested_organization_workspace_id']::text[]
    OR output_names IS DISTINCT FROM ARRAY['organization_shareable_join_application_directory_contract_id', 'organization_workspace_id', 'observed_at_utc', 'applications']::text[]
    OR output_types IS DISTINCT FROM ARRAY['text', 'uuid', 'timestamp with time zone', 'jsonb']::text[]
  THEN RAISE EXCEPTION '0099 directory exact signature drift'; END IF;
  IF NOT has_function_privilege('tongxingzhe_runtime', reader, 'EXECUTE') OR EXISTS (
    SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE p.oid = reader AND (a.grantee NOT IN (trusted_owner, runtime_role) OR a.privilege_type <> 'EXECUTE' OR a.is_grantable)
  ) OR has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
  THEN RAISE EXCEPTION '0099 directory minimal ACL drift'; END IF;
  FOREACH relation IN ARRAY ARRAY[
    'app_data.external_identities'::regclass, 'app_data.app_users'::regclass,
    'app_data.workspaces'::regclass, 'app_data.organization_memberships'::regclass,
    'app_data.organization_owner_assignments'::regclass,
    'app_private.organization_shareable_join_application_request_claims'::regclass,
    'app_private.organization_shareable_join_application_request_tombstones'::regclass,
    'app_private.organization_shareable_join_application_audit_events'::regclass
  ] LOOP
    IF has_table_privilege('tongxingzhe_runtime', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    THEN RAISE EXCEPTION '0099 directory granted runtime relation access: %', relation; END IF;
  END LOOP;
  IF regexp_count(definition, 'clock_timestamp[(][)]') <> 1
    OR regexp_count(definition, 'RETURN QUERY') <> 1
    OR definition NOT LIKE '%WITH observation AS MATERIALIZED%'
    OR definition NOT LIKE '%identity_row.issuer = trusted_issuer AND identity_row.subject = trusted_subject%'
    OR definition NOT LIKE '%claim.approved_at_utc IS NULL%claim.approved_organization_membership_id IS NULL%'
    OR definition NOT LIKE '%observation.observed_at_utc < claim.expires_at_utc%'
    OR definition NOT LIKE '%ORDER BY claim.submitted_at_utc, claim.application_id%LIMIT 20%'
    OR regexp_count(definition, '@> observation[.]observed_at_utc') <> 2
    OR definition NOT LIKE '%tstzrange(parent.active_from_utc, parent.inactive_from_utc, ''[)'') @> observation.observed_at_utc%'
    OR definition NOT LIKE '%tstzrange(owner_assignment.active_from_utc, owner_assignment.inactive_from_utc, ''[)'') @> observation.observed_at_utc%'
    OR definition ~* '\m(insert|update|delete|merge|truncate|pg_advisory|for share|for update)\M'
    OR definition ~* 'app_private[.]organization_shareable_join_link|app_data[.](projects|project_memberships|management_report_capability_grants)'
    OR definition ~* 'claim[.]applicant_app_user_id'
  THEN RAISE EXCEPTION '0099 directory single-observation read-only pending query drift'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version = '0099_organization_shareable_join_application_directory') <> 1
  THEN RAISE EXCEPTION '0099 migration not recorded once'; END IF;
END
$check$;
