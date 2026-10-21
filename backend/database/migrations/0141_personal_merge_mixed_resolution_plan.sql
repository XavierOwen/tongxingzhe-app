CREATE FUNCTION app_private.plan_personal_merge_mixed_resolutions_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_generation_id uuid,
  expected_known_fact_fingerprint text,
  expected_contact_pending_fingerprint text,
  expected_project_pending_fingerprint text,
  requested_contact_assignments jsonb,
  requested_project_assignments jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  contact_plan jsonb;
  project_plan jsonb;
  fingerprint_metadata jsonb;
BEGIN
  IF requested_contact_assignments IS NULL OR jsonb_typeof(requested_contact_assignments) <> 'array'
    OR requested_project_assignments IS NULL OR jsonb_typeof(requested_project_assignments) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'mixed resolution plan requires nonempty assignment arrays';
  END IF;
  IF jsonb_array_length(requested_contact_assignments) = 0 OR jsonb_array_length(requested_project_assignments) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'mixed resolution plan requires nonempty assignment arrays';
  END IF;

  -- STABLE subplans share the outer command's snapshot without reserving write eligibility.
  contact_plan := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_contact_pending_fingerprint, requested_contact_assignments);
  project_plan := app_private.plan_personal_merge_project_relationship_resolutions_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_project_pending_fingerprint, requested_project_assignments);
  IF contact_plan->'known_source_plan' IS DISTINCT FROM project_plan->'known_source_plan' THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'mixed resolution plan snapshots disagree';
  END IF;
  fingerprint_metadata := jsonb_build_object(
    'contract_id', 'personal_merge_mixed_resolution_plan_v1',
    'contact_resolution_plan', contact_plan,
    'project_relationship_resolution_plan', project_plan);
  RETURN fingerprint_metadata || jsonb_build_object('resolution_fingerprint',
    encode(sha256(convert_to(fingerprint_metadata::text, 'UTF8')), 'hex'));
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.plan_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.plan_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb) OWNER TO %I', trusted_owner);
END
$owner$;
