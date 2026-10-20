\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  candidate regprocedure;
  relation regclass;
  columns text[];
  types oid[];
  nullable text[];
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0134_personal_history_contribution') <> 1
  THEN RAISE EXCEPTION '0134 personal history contribution migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF has_schema_privilege('public', 'app_private', 'USAGE')
    OR has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
  THEN RAISE EXCEPTION '0134 personal history contribution cannot open the private schema'; END IF;

  FOREACH candidate IN ARRAY ARRAY[
    'app_private.lock_personal_history_contribution_context_v1(uuid,text,uuid)'::regprocedure,
    'app_private.preview_personal_history_contribution_v1(uuid,text,uuid)'::regprocedure,
    'app_private.confirm_personal_history_contribution_v1(uuid,uuid,uuid)'::regprocedure,
    'app_private.protect_personal_history_contribution_provenance_v1()'::regprocedure
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate
        AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
        AND proconfig = ARRAY['search_path=pg_catalog']::text[])
      OR has_function_privilege('public', candidate, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', candidate, 'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
        WHERE p.oid = candidate AND acl.grantee <> p.proowner)
    THEN RAISE EXCEPTION '0134 private function owner, security or ACL drift: %', candidate; END IF;
  END LOOP;
  IF pg_get_function_result('app_private.lock_personal_history_contribution_context_v1(uuid,text,uuid)'::regprocedure)
      IS DISTINCT FROM 'timestamp with time zone'
    OR pg_get_function_result('app_private.preview_personal_history_contribution_v1(uuid,text,uuid)'::regprocedure)
      IS DISTINCT FROM 'TABLE(contribution_preview_contract_id text, preview_id uuid, source_revision_number integer, target_project_id uuid, issued_at_utc timestamp with time zone, expires_at_utc timestamp with time zone, occurred_at_utc timestamp with time zone, occurred_time_zone text, channel text, reach_count integer, interest_level integer)'
    OR pg_get_function_result('app_private.confirm_personal_history_contribution_v1(uuid,uuid,uuid)'::regprocedure)
      IS DISTINCT FROM 'TABLE(contribution_contract_id text, copy_id uuid, target_project_id uuid, confirmed_at_utc timestamp with time zone)'
    OR pg_get_function_result('app_private.protect_personal_history_contribution_provenance_v1()'::regprocedure)
      IS DISTINCT FROM 'trigger'
  THEN RAISE EXCEPTION '0134 contribution exact typed result drift'; END IF;

  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_history_contribution_previews_v1'::regclass,
    'app_private.organization_historical_contact_copies_v1'::regclass,
    'app_private.personal_history_contribution_confirmations_v1'::regclass
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation AND relkind = 'r' AND relowner = trusted_owner)
      OR has_table_privilege('public', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class c
        CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
        WHERE c.oid = relation AND acl.grantee <> c.relowner)
    THEN RAISE EXCEPTION '0134 contribution table owner or ACL drift: %', relation; END IF;
    CASE relation
      WHEN 'app_private.personal_history_contribution_previews_v1'::regclass THEN
        columns := ARRAY['preview_id', 'actor_app_user_id', 'source_contact_id', 'source_revision_number',
          'target_project_id', 'issued_at_utc', 'expires_at_utc'];
        types := ARRAY['uuid'::regtype, 'uuid'::regtype, 'text'::regtype, 'int4'::regtype,
          'uuid'::regtype, 'timestamptz'::regtype, 'timestamptz'::regtype];
        nullable := ARRAY['actor_app_user_id', 'source_contact_id'];
      WHEN 'app_private.organization_historical_contact_copies_v1'::regclass THEN
        columns := ARRAY['copy_id', 'target_project_id', 'occurred_at_utc', 'occurred_time_zone',
          'channel', 'reach_count', 'interest_level', 'confirmed_at_utc'];
        types := ARRAY['uuid'::regtype, 'uuid'::regtype, 'timestamptz'::regtype, 'text'::regtype,
          'text'::regtype, 'int4'::regtype, 'int4'::regtype, 'timestamptz'::regtype];
        nullable := ARRAY[]::text[];
      ELSE
        columns := ARRAY['request_id', 'actor_app_user_id', 'source_contact_id', 'target_project_id',
          'preview_id', 'copy_id', 'confirmed_at_utc'];
        types := ARRAY['uuid'::regtype, 'uuid'::regtype, 'text'::regtype, 'uuid'::regtype,
          'uuid'::regtype, 'uuid'::regtype, 'timestamptz'::regtype];
        nullable := ARRAY['actor_app_user_id', 'source_contact_id'];
    END CASE;
    IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped) IS DISTINCT FROM columns
      OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped) IS DISTINCT FROM types
      OR (SELECT coalesce(array_agg(attname::text ORDER BY attnum), ARRAY[]::text[]) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped AND NOT attnotnull) IS DISTINCT FROM nullable
      OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = relation AND contype = 'p'
        AND conkey = ARRAY[1]::smallint[] AND NOT condeferrable AND convalidated)
      OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = relation AND NOT tgisinternal
        AND tgenabled = 'O' AND tgtype = 27
        AND tgfoid = CASE WHEN relation = 'app_private.organization_historical_contact_copies_v1'::regclass
          THEN 'app_data.reject_promotion_target_audit_mutation()'::regprocedure
          ELSE 'app_private.protect_personal_history_contribution_provenance_v1()'::regprocedure END) <> 1
    THEN RAISE EXCEPTION '0134 contribution typed allowlist, primary key or immutable trigger drift: %', relation; END IF;
  END LOOP;

  IF EXISTS (
    WITH expected(name, source_table, source_column, target_table, target_column, on_delete) AS (VALUES
      ('phc_preview_actor_fk', 'personal_history_contribution_previews_v1', 2, 'app_data.app_users', 1, 'n'),
      ('phc_preview_source_fk', 'personal_history_contribution_previews_v1', 3, 'app_data.contacts', 1, 'n'),
      ('phc_preview_project_fk', 'personal_history_contribution_previews_v1', 5, 'app_data.projects', 1, 'r'),
      ('phc_copy_project_fk', 'organization_historical_contact_copies_v1', 2, 'app_data.projects', 1, 'r'),
      ('phc_confirm_actor_fk', 'personal_history_contribution_confirmations_v1', 2, 'app_data.app_users', 1, 'n'),
      ('phc_confirm_source_fk', 'personal_history_contribution_confirmations_v1', 3, 'app_data.contacts', 1, 'n'),
      ('phc_confirm_project_fk', 'personal_history_contribution_confirmations_v1', 4, 'app_data.projects', 1, 'r'),
      ('phc_confirm_preview_fk', 'personal_history_contribution_confirmations_v1', 5, 'app_private.personal_history_contribution_previews_v1', 1, 'r'),
      ('phc_confirm_copy_fk', 'personal_history_contribution_confirmations_v1', 6, 'app_private.organization_historical_contact_copies_v1', 1, 'r')
    ) SELECT 1 FROM expected e LEFT JOIN pg_constraint c
      ON c.conname = e.name AND c.conrelid = to_regclass('app_private.' || e.source_table)
      AND c.contype = 'f' AND c.confrelid = to_regclass(e.target_table)
      AND c.conkey = ARRAY[e.source_column]::smallint[] AND c.confkey = ARRAY[e.target_column]::smallint[]
      AND c.confdeltype::text = e.on_delete AND c.confupdtype = 'a'
      AND NOT c.condeferrable AND NOT c.condeferred AND c.convalidated
    WHERE c.oid IS NULL
  ) OR (SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND conrelid IN (
      'app_private.personal_history_contribution_previews_v1'::regclass,
      'app_private.organization_historical_contact_copies_v1'::regclass,
      'app_private.personal_history_contribution_confirmations_v1'::regclass)) <> 9
  THEN RAISE EXCEPTION '0134 contribution requires exactly nine named immediate foreign keys'; END IF;
  IF (SELECT count(*) FROM pg_constraint
      WHERE conrelid = 'app_private.personal_history_contribution_confirmations_v1'::regclass AND contype = 'u'
      AND conkey IN (ARRAY[4, 3]::smallint[], ARRAY[5]::smallint[], ARRAY[6]::smallint[])
      AND NOT condeferrable AND convalidated) <> 3
  THEN RAISE EXCEPTION '0134 contribution source/project, preview or copy uniqueness drift'; END IF;
END
$check$;
