\set ON_ERROR_STOP on

DO $check$
DECLARE
  private_writer regprocedure := to_regprocedure(
    'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'
  );
  private_definition text;
  membership_lock_position integer;
  replay_position integer;
  authorization_position integer;
  first_authorization_range_position integer;
  effective_position integer;
BEGIN
  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0088_organization_owner_transfer_authorization_time'
  ) <> 1 THEN
    RAISE EXCEPTION
      '0088 owner transfer authorization-time migration was not recorded once';
  END IF;

  IF private_writer IS NULL THEN
    RAISE EXCEPTION 'organization owner transfer private writer is missing';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(private_writer)
  INTO STRICT private_definition;

  IF pg_catalog.regexp_count(
       private_definition,
       'authorization_time[[:space:]]*:[=][[:space:]]*clock_timestamp[[:space:]]*[(][)]'
     ) <> 1
    OR pg_catalog.regexp_count(
      private_definition,
      'effective_time[[:space:]]*:[=][[:space:]]*transaction_timestamp[[:space:]]*[(][)]'
    ) <> 1
    OR pg_catalog.regexp_count(
      private_definition,
      '@>[[:space:]]*authorization_time'
    ) <> 4
    OR pg_catalog.regexp_count(
      private_definition,
      '@>[[:space:]]*effective_time'
    ) <> 0
  THEN
    RAISE EXCEPTION
      '0088 owner transfer authorization-time expressions drifted';
  END IF;

  membership_lock_position := pg_catalog.strpos(
    private_definition,
    'FOR membership_lock_row IN'
  );
  replay_position := pg_catalog.strpos(
    pg_catalog.substr(private_definition, membership_lock_position),
    'SELECT claim.*'
  );
  IF membership_lock_position <= 0 OR replay_position <= 0 THEN
    RAISE EXCEPTION
      '0088 owner transfer lock-after replay markers are missing';
  END IF;
  replay_position := membership_lock_position + replay_position - 1;

  authorization_position := pg_catalog.regexp_instr(
    private_definition,
    'authorization_time[[:space:]]*:[=][[:space:]]*clock_timestamp[[:space:]]*[(][)]'
  );
  first_authorization_range_position := pg_catalog.regexp_instr(
    private_definition,
    '@>[[:space:]]*authorization_time'
  );
  effective_position := pg_catalog.regexp_instr(
    private_definition,
    'effective_time[[:space:]]*:[=][[:space:]]*transaction_timestamp[[:space:]]*[(][)]'
  );

  IF authorization_position <= replay_position
    OR authorization_position >= first_authorization_range_position
    OR effective_position <= authorization_position
  THEN
    RAISE EXCEPTION
      '0088 owner transfer authorization time is captured at the wrong point';
  END IF;
END
$check$;
