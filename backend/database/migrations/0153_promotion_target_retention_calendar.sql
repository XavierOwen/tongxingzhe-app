-- Retention uses UTC calendar months and a continuous 720-hour review horizon.
DO $calendar$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  calculation record;
BEGIN
  FOR calculation IN
    SELECT * FROM (VALUES
      (
        'app_data.promotion_target_review_due_at(uuid)',
        $old$app_data.promotion_target_retention_reference_at(
      target_row.promotion_target_id
    ) + make_interval(months => COALESCE(
      policy_row.retention_months,
      12
    ))$old$,
        $new$pg_catalog.date_add(app_data.promotion_target_retention_reference_at(
      target_row.promotion_target_id
    ), make_interval(months => COALESCE(
      policy_row.retention_months,
      12
    )), 'UTC')$new$
      ),
      (
        'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)',
        $old$event_time + make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12))$old$,
        $new$pg_catalog.date_add(GREATEST(event_time,
        app_data.promotion_target_retention_reference_at(requested_target_id)
      ), make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12)), 'UTC')$new$
      ),
      (
        'app_data.list_promotion_target_retention_tasks(uuid,uuid,uuid)',
        $old$clock_timestamp() + interval '30 days'$old$,
        $new$clock_timestamp() + interval '720 hours'$new$
      )
    ) AS calculations(signature, old_expression, new_expression)
  LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = calculation.signature::regprocedure;
    definition := pg_catalog.pg_get_functiondef(original.oid);
    IF length(original.prosrc) - length(replace(original.prosrc, calculation.old_expression, ''))
        <> length(calculation.old_expression)
      OR position(calculation.new_expression IN original.prosrc) <> 0 THEN
      RAISE EXCEPTION '0153 retention calendar anchor unavailable: %', calculation.signature;
    END IF;
    EXECUTE replace(definition, calculation.old_expression, calculation.new_expression);
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc changed
      WHERE changed.oid = original.oid
        AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
        AND replace(changed.prosrc, calculation.new_expression, '')
          = replace(original.prosrc, calculation.old_expression, '')
    ) THEN
      RAISE EXCEPTION '0153 retention calendar changed metadata or unrelated implementation: %',
        calculation.signature;
    END IF;
  END LOOP;
END
$calendar$;
