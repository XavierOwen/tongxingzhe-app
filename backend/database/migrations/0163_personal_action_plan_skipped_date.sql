-- A skipped configured start date can resolve to the following local date.
CREATE FUNCTION app_private.personal_action_plan_cycle_until_v2(
  resolved_cycle_start_utc timestamptz, requested_statistics_time_zone text,
  requested_week_start_iso_day integer
)
RETURNS timestamptz LANGUAGE sql STABLE PARALLEL SAFE
RETURN app_private.personal_action_plan_local_midnight_v1(
  (resolved_cycle_start_utc AT TIME ZONE requested_statistics_time_zone)::date
    - ((extract(isodow FROM resolved_cycle_start_utc AT TIME ZONE requested_statistics_time_zone)::integer
      - requested_week_start_iso_day + 7) % 7) + 7,
  requested_statistics_time_zone
);

REVOKE ALL ON FUNCTION app_private.personal_action_plan_cycle_until_v2(timestamptz,text,integer)
  FROM PUBLIC, tongxingzhe_runtime;

DO $skipped_date$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  signature text;
  source text;
  anchor text;
  replacement text;
  trusted_owner name;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'app_data.personal_action_plan_document(uuid,timestamptz)',
    'app_data.save_personal_action_plan(uuid,uuid,uuid,integer,integer,text,integer,text,timestamptz)'
  ] LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc WHERE oid = signature::regprocedure;
    IF original.proname = 'personal_action_plan_document' THEN
      anchor := $anchor$  cycle_until_utc := app_data.personal_action_plan_cycle_until(
    cycle_start_utc,
    current_version.statistics_time_zone
  );$anchor$;
      replacement := $replacement$  cycle_until_utc := app_private.personal_action_plan_cycle_until_v2(
    cycle_start_utc,
    current_version.statistics_time_zone,
    current_version.week_start_iso_day
  );$replacement$;
    ELSE
      anchor := $anchor$    effective_from_utc := app_data.personal_action_plan_cycle_until(
      app_data.personal_action_plan_cycle_start(
        trusted_requested_at_utc,
        normalized_time_zone,
        requested_week_start_iso_day
      ),
      normalized_time_zone
    );$anchor$;
      replacement := $replacement$    effective_from_utc := app_private.personal_action_plan_cycle_until_v2(
      app_data.personal_action_plan_cycle_start(
        trusted_requested_at_utc,
        normalized_time_zone,
        requested_week_start_iso_day
      ),
      normalized_time_zone,
      requested_week_start_iso_day
    );$replacement$;
    END IF;
    IF length(original.prosrc) - length(replace(original.prosrc, anchor, '')) <> length(anchor) THEN
      RAISE EXCEPTION '0163 personal plan cycle-until call anchor unavailable: %', signature;
    END IF;
    source := replace(original.prosrc, anchor, replacement);
    EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, source);
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc' AND changed.prosrc = source) THEN
      RAISE EXCEPTION '0163 personal plan caller changed metadata or unrelated implementation: %', signature;
    END IF;
  END LOOP;
  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_catalog.pg_proc
    WHERE oid = 'app_data.personal_action_plan_cycle_start(timestamptz,text,integer)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.personal_action_plan_cycle_until_v2(timestamptz,text,integer) OWNER TO %I', trusted_owner);
END
$skipped_date$;
