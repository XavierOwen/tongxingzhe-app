-- Resolve both sides of a midnight fold without changing PostgreSQL's gap policy.
CREATE FUNCTION app_private.personal_action_plan_local_midnight_v1(
  requested_local_date date, requested_statistics_time_zone text
)
RETURNS timestamptz LANGUAGE sql STABLE PARALLEL SAFE
RETURN (
  WITH midnight AS (
    SELECT requested_local_date::timestamp AS local_midnight,
      pg_catalog.timezone(requested_statistics_time_zone, requested_local_date::timestamp) AS nominal_utc
  ), candidates AS (
    SELECT local_midnight, nominal_utc,
      pg_catalog.timezone('UTC', local_midnight)
        - (pg_catalog.timezone(requested_statistics_time_zone, sampled.instant)
          - pg_catalog.timezone('UTC', sampled.instant)) AS candidate_utc
    FROM midnight CROSS JOIN LATERAL pg_catalog.unnest(ARRAY[
      nominal_utc - interval '24 hours', nominal_utc, nominal_utc + interval '24 hours'
    ]) AS sampled(instant)
  )
  SELECT coalesce(pg_catalog.min(candidate_utc)
    FILTER (WHERE pg_catalog.timezone(requested_statistics_time_zone, candidate_utc) = local_midnight),
    pg_catalog.min(nominal_utc))
  FROM candidates
);

REVOKE ALL ON FUNCTION app_private.personal_action_plan_local_midnight_v1(date,text)
  FROM PUBLIC, tongxingzhe_runtime;

DO $midnight_fold$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  signature text;
  source text;
  anchor text;
  replacement text;
  trusted_owner name;
  legacy_start text := $legacy$
  SELECT (
    (
      (reference_at_utc AT TIME ZONE statistics_time_zone)::date
      - (
        (
          extract(
            isodow FROM reference_at_utc AT TIME ZONE statistics_time_zone
          )::integer
          - week_start_iso_day
          + 7
        ) % 7
      )
    )::timestamp AT TIME ZONE statistics_time_zone
  );
$legacy$;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'app_data.personal_action_plan_cycle_start(timestamptz,text,integer)',
    'app_data.personal_action_plan_cycle_until(timestamptz,text)'
  ] LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc WHERE oid = signature::regprocedure;
    IF original.proname = 'personal_action_plan_cycle_start' THEN
      IF original.prosrc <> legacy_start THEN
        RAISE EXCEPTION '0162 personal plan cycle-start implementation drift';
      END IF;
      -- A rollback into the previous local date must not reopen the ended week.
      source := $source$
  WITH nominal AS (
    SELECT (reference_at_utc AT TIME ZONE statistics_time_zone)::date
      - ((extract(isodow FROM reference_at_utc AT TIME ZONE statistics_time_zone)::integer
        - week_start_iso_day + 7) % 7) AS cycle_date
  )
  SELECT pg_catalog.max(candidates.cycle_start_utc)
  FROM nominal CROSS JOIN LATERAL (VALUES
    (app_private.personal_action_plan_local_midnight_v1(cycle_date, statistics_time_zone)),
    (app_private.personal_action_plan_local_midnight_v1(cycle_date + 7, statistics_time_zone))
  ) AS candidates(cycle_start_utc)
  WHERE candidates.cycle_start_utc <= reference_at_utc;
$source$;
    ELSE
      anchor := E'  SELECT (\n';
      IF length(original.prosrc) - length(replace(original.prosrc, anchor, '')) <> length(anchor) THEN
        RAISE EXCEPTION '0162 personal plan boundary SELECT anchor unavailable: %', signature;
      END IF;
      source := replace(original.prosrc, anchor, E'  SELECT app_private.personal_action_plan_local_midnight_v1(\n');
      anchor := $anchor$    ((cycle_start_utc AT TIME ZONE statistics_time_zone)::date + 7)::timestamp
    AT TIME ZONE statistics_time_zone$anchor$;
      replacement := '    ((cycle_start_utc AT TIME ZONE statistics_time_zone)::date + 7), statistics_time_zone';
      IF length(source) - length(replace(source, anchor, '')) <> length(anchor) THEN
        RAISE EXCEPTION '0162 personal plan local-date anchor unavailable: %', signature;
      END IF;
      source := replace(source, anchor, replacement);
    END IF;
    EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, source);
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc' AND changed.prosrc = source) THEN
      RAISE EXCEPTION '0162 personal plan boundary changed metadata or unrelated implementation: %', signature;
    END IF;
  END LOOP;
  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_catalog.pg_proc
    WHERE oid = 'app_data.personal_action_plan_cycle_start(timestamptz,text,integer)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.personal_action_plan_local_midnight_v1(date,text) OWNER TO %I', trusted_owner);
END
$midnight_fold$;
