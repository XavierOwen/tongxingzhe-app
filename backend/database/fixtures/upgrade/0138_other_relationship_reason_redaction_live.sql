\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

-- Keep the real 0138 confirmation, including both same-valued other histories.
SELECT public.fixture_0137_confirmation_assert_upgrade();
CREATE TABLE public.fixture_0138_redaction_context AS
SELECT c.*, target.target_id FROM public.fixture_0135_project_context c
JOIN public.fixture_0136_resolution_targets target ON target.ordinal = 1;
SELECT result FROM public.fixture_0138_redaction_context c
JOIN app_data.promotion_target_project_relationships r
  ON r.promotion_target_id=c.target_id AND r.project_id=c.project_id
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  c.target_id,r.current_revision,4,'active','0138 ordinary private note','other','0138 ordinary private reason',
  '0138-redaction-other',NULL);
SELECT result FROM public.fixture_0138_redaction_context c
JOIN app_data.promotion_target_project_relationships r
  ON r.promotion_target_id=c.target_id AND r.project_id=c.project_id
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  c.target_id,r.current_revision,3,'active','0138 nonother private note','correction','0138 correction private reason',
  '0138-redaction-nonother',NULL);
CREATE TABLE public.fixture_0138_redaction_revisions AS
SELECT r.* FROM app_data.promotion_target_relationship_revisions r
JOIN public.fixture_0138_redaction_context c ON c.target_id=r.promotion_target_id;
CREATE TABLE public.fixture_0138_redaction_parent AS
SELECT r.* FROM app_data.promotion_target_project_relationships r
JOIN public.fixture_0138_redaction_context c ON c.target_id=r.promotion_target_id;
CREATE TABLE public.fixture_0138_redaction_relations AS
SELECT c.oid,n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r';
CREATE TABLE public.fixture_0138_redaction_delta(old_clause text,new_clause text);
INSERT INTO public.fixture_0138_redaction_delta VALUES (
$old$  SET follow_up_note = NULL, reason_detail = NULL,
      requested_follow_up_note = NULL
  WHERE promotion_target_id = requested_target_id
    AND (follow_up_note IS NOT NULL OR reason_detail IS NOT NULL
      OR requested_follow_up_note IS NOT NULL);$old$,
$new$  SET follow_up_note = NULL,
      reason_detail = CASE WHEN reason_code = 'other'
        THEN '[已匿名化]' ELSE NULL END,
      requested_follow_up_note = NULL
  WHERE promotion_target_id = requested_target_id
    AND (follow_up_note IS NOT NULL OR reason_detail IS NOT NULL
      OR requested_follow_up_note IS NOT NULL);$new$);
CREATE FUNCTION public.fixture_0138_redaction_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog',CASE WHEN p.oid=
      'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)'::regprocedure
      THEN jsonb_set(to_jsonb(p),'{prosrc}',to_jsonb(replace(p.prosrc,d.new_clause,d.old_clause))) ELSE to_jsonb(p) END,
    'definition',CASE WHEN p.oid='app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)'::regprocedure
      THEN replace(pg_get_functiondef(p.oid),d.new_clause,d.old_clause) ELSE pg_get_functiondef(p.oid) END) ORDER BY p.oid)
  FROM pg_proc p CROSS JOIN public.fixture_0138_redaction_delta d
  WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
$function$;
CREATE FUNCTION public.fixture_0138_redaction_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',n.nspname,'name',c.relname,'kind',c.relkind,
    'owner',c.relowner,'acl',c.relacl,'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0),
    'constraints',(SELECT jsonb_agg(jsonb_build_object('catalog',to_jsonb(k),'definition',pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid=c.oid),
    'triggers',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t WHERE t.tgrelid=c.oid),
    'index',(SELECT to_jsonb(i) FROM pg_index i WHERE i.indexrelid=c.oid),
    'view',CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid) END) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('app_data','app_private')
$function$;
CREATE FUNCTION public.fixture_0138_redaction_business_state(allow_redaction boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb:='{}'::jsonb; expression text; predicate text;
  selected_target uuid:=(SELECT target_id FROM public.fixture_0138_redaction_context);
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0138_redaction_relations ORDER BY nspname,relname LOOP
    expression:='to_jsonb(r)'; predicate:='true';
    IF allow_redaction THEN
      IF relation.nspname='app_private' AND relation.relname='personal_target_merge_generation_fence_v1' THEN
        expression:='to_jsonb(r) - ''epoch''';
      ELSIF relation.nspname='app_data' THEN
        IF relation.relname='promotion_target_relationship_revisions' THEN
          expression:=format('CASE WHEN r.promotion_target_id=%L::uuid THEN to_jsonb(r)-ARRAY[''follow_up_note'',''reason_detail'',''requested_follow_up_note''] ELSE to_jsonb(r) END',selected_target);
          predicate:='EXISTS(SELECT 1 FROM public.fixture_0138_redaction_revisions old WHERE old.promotion_target_id=r.promotion_target_id AND old.project_id=r.project_id AND old.revision_number=r.revision_number) OR r.promotion_target_id<>(SELECT target_id FROM public.fixture_0138_redaction_context)';
        ELSIF relation.relname='promotion_target_relationship_conflicts' THEN
          expression:=format('CASE WHEN r.promotion_target_id=%L::uuid THEN to_jsonb(r)-ARRAY[''proposed_follow_up_note'',''proposed_reason_detail''] ELSE to_jsonb(r) END',selected_target);
        ELSIF relation.relname='promotion_targets' THEN
          expression:=format('CASE WHEN r.promotion_target_id=%L::uuid THEN to_jsonb(r)-ARRAY[''display_name'',''phone'',''email'',''status'',''anonymized_at'',''anonymization_reason''] ELSE to_jsonb(r) END',selected_target);
        ELSIF relation.relname='promotion_target_project_relationships' THEN
          expression:=format('CASE WHEN r.promotion_target_id=%L::uuid THEN to_jsonb(r)-ARRAY[''current_lifecycle_status'',''current_follow_up_note'',''current_revision'',''updated_by_app_user_id'',''updated_at''] ELSE to_jsonb(r) END',selected_target);
        ELSIF relation.relname='promotion_target_assignments' THEN
          expression:=format('CASE WHEN r.promotion_target_id=%L::uuid THEN to_jsonb(r)-ARRAY[''ended_at'',''end_reason''] ELSE to_jsonb(r) END',selected_target);
        ELSIF relation.relname='promotion_target_retention_events' THEN
          predicate:='mutation_id<>''0138-redaction-withdrawal''';
        END IF;
      END IF;
    END IF;
    EXECUTE format('SELECT coalesce(jsonb_agg(%s ORDER BY (%s)::text),''[]''::jsonb) FROM %I.%I r WHERE %s',
      expression,expression,relation.nspname,relation.relname,predicate) INTO rows;
    state:=state||jsonb_build_object(relation.nspname||'.'||relation.relname,rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE TABLE public.fixture_0138_redaction_state AS
SELECT public.fixture_0138_redaction_business_state() AS business_state,
  public.fixture_0138_redaction_business_state(true) AS preserved_state,
  public.fixture_0138_redaction_function_catalog() AS function_catalog,
  public.fixture_0138_redaction_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)<>'0138_personal_merge_project_relationship_resolution_confirmation'
    OR (SELECT count(*) FROM public.fixture_0138_redaction_parent)<>1
    OR (SELECT count(*) FROM public.fixture_0138_redaction_revisions WHERE reason_code='other' AND reason_detail IS NOT NULL)<>3
    OR (SELECT count(*) FROM public.fixture_0138_redaction_revisions WHERE changed_fields=ARRAY['pending_source_assignment']::text[] AND reason_code='other')<>2
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0138_redaction_revisions WHERE mutation_id='0138-redaction-other'
      AND reason_code='other' AND reason_detail='0138 ordinary private reason')
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0138_redaction_revisions WHERE mutation_id='0138-redaction-nonother'
      AND reason_code='correction' AND reason_detail='0138 correction private reason')
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0138_redaction_parent WHERE current_stage=3
      AND current_lifecycle_status='active' AND current_follow_up_note='0138 nonother private note')
    OR EXISTS(SELECT 1 FROM app_data.promotion_target_institution_relationships r CROSS JOIN public.fixture_0138_redaction_context c
      WHERE r.person_target_id=c.target_id OR r.institution_target_id=c.target_id)
    OR EXISTS(SELECT 1 FROM app_private.personal_target_merge_active_members_v1 m
      JOIN public.fixture_0138_redaction_context c ON m.promotion_target_id=c.target_id)
  THEN RAISE EXCEPTION '0138 redaction baseline lacks ordinary/confirmed other, nonother or ended merge'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0138_redaction_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0138_redaction_state%ROWTYPE; c public.fixture_0138_redaction_context%ROWTYPE;
  result jsonb; replayed jsonb; after_state jsonb; event_time timestamptz; source text; d record;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0138_redaction_state;
  SELECT * INTO STRICT c FROM public.fixture_0138_redaction_context;
  SELECT * INTO STRICT d FROM public.fixture_0138_redaction_delta;
  SELECT prosrc INTO STRICT source FROM pg_proc
    WHERE oid='app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)'::regprocedure;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version<>'0139_other_relationship_reason_redaction') IS DISTINCT FROM saved.migrations
    OR (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0139_other_relationship_reason_redaction')<>1
    OR public.fixture_0138_redaction_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0138_redaction_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0138_redaction_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR length(source)-length(replace(source,d.new_clause,''))<>length(d.new_clause)
    OR position(d.old_clause IN source)<>0
  THEN RAISE EXCEPTION '0139 migration changed old rows/catalog or more than the exact revision SET clause'; END IF;
  SELECT a.result INTO STRICT result FROM app_data.apply_promotion_target_retention_action(c.app_user_id,c.workspace_id,
    c.project_id,c.target_id,'anonymize','withdrawal','0138-redaction-withdrawal') a;
  SELECT occurred_at INTO STRICT event_time FROM app_data.promotion_target_retention_events
    WHERE actor_app_user_id=c.app_user_id AND mutation_id='0138-redaction-withdrawal';
  IF result IS DISTINCT FROM jsonb_build_object('target_id',c.target_id,'status','anonymized','duplicate',false,'review_due_at',NULL)
    OR public.fixture_0138_redaction_business_state(true) IS DISTINCT FROM saved.preserved_state
    OR EXISTS(SELECT 1 FROM app_data.promotion_target_relationship_revisions r WHERE r.promotion_target_id=c.target_id
      AND (r.follow_up_note IS NOT NULL OR r.requested_follow_up_note IS NOT NULL
        OR r.reason_detail IS DISTINCT FROM CASE WHEN r.reason_code='other' THEN '[已匿名化]' ELSE NULL END))
    OR EXISTS(SELECT 1 FROM app_data.promotion_target_relationship_conflicts r WHERE r.promotion_target_id=c.target_id
      AND (r.proposed_follow_up_note IS NOT NULL OR r.proposed_reason_detail IS NOT NULL))
    OR NOT EXISTS(SELECT 1 FROM app_data.promotion_targets t WHERE t.promotion_target_id=c.target_id
      AND t.display_name='已匿名化对象' AND t.phone IS NULL AND t.email IS NULL AND t.status='anonymized'
      AND t.anonymized_at=event_time AND t.anonymization_reason='withdrawal')
    OR EXISTS(SELECT 1 FROM app_data.promotion_target_assignments a WHERE a.promotion_target_id=c.target_id
      AND (a.ended_at IS DISTINCT FROM event_time OR a.end_reason IS DISTINCT FROM 'target_anonymized'))
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions WHERE promotion_target_id=c.target_id)
      <>(SELECT count(*)+1 FROM public.fixture_0138_redaction_revisions)
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0138_redaction_parent old
      JOIN app_data.promotion_target_project_relationships r USING(promotion_target_id,project_id)
      JOIN app_data.promotion_target_relationship_revisions v ON v.promotion_target_id=r.promotion_target_id
        AND v.project_id=r.project_id AND v.revision_number=r.current_revision
      WHERE r.current_revision=old.current_revision+1 AND r.current_lifecycle_status='ended'
        AND r.current_follow_up_note IS NULL AND r.updated_by_app_user_id=c.app_user_id AND r.updated_at=event_time
        AND v.old_stage=old.current_stage AND v.new_stage=old.current_stage AND v.old_lifecycle_status=old.current_lifecycle_status
        AND v.new_lifecycle_status='ended' AND v.reason_code='target_request'
        AND v.changed_fields=ARRAY['lifecycle_status','follow_up_note']::text[]
        AND v.changed_by_app_user_id=c.app_user_id AND v.changed_at=event_time
        AND v.merge_generation_id IS NULL AND v.mutation_id IS NULL AND v.requested_base_revision IS NULL
        AND v.requested_stage IS NULL AND v.requested_lifecycle_status IS NULL AND v.resolved_conflict_id IS NULL)
  THEN RAISE EXCEPTION '0139 retention failed exact redaction, preserved metadata, end revision or unrelated facts'; END IF;
  after_state:=public.fixture_0138_redaction_business_state();
  SELECT a.result INTO STRICT replayed FROM app_data.apply_promotion_target_retention_action(c.app_user_id,c.workspace_id,
    c.project_id,c.target_id,'anonymize','withdrawal','0138-redaction-withdrawal') a;
  IF replayed IS DISTINCT FROM result||jsonb_build_object('duplicate',true)
    OR public.fixture_0138_redaction_business_state() IS DISTINCT FROM after_state
    OR public.fixture_0138_redaction_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0138_redaction_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0139 exact retention replay changed redacted facts or catalog'; END IF;
END $function$;
COMMIT;
