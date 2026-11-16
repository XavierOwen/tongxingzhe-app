-- Keep contact IDs intact; only long internal command keys need a bounded suffix.
CREATE FUNCTION app_private.personal_merge_contact_child_key_v1(requested_contact_id text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN CASE WHEN pg_catalog.octet_length(requested_contact_id) <= 2048
  THEN pg_catalog.octet_length(requested_contact_id)::text || ':' || requested_contact_id
  ELSE 'sha256-v2:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(requested_contact_id, 'UTF8')), 'hex')
END;

REVOKE ALL ON FUNCTION app_private.personal_merge_contact_child_key_v1(text) FROM PUBLIC, tongxingzhe_runtime;

DO $bounded_commands$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  candidate record;
  source text;
  alias text;
  old_key text;
  anchor text;
  replacement text;
  aliases text[] := ARRAY['contact_id', 'pending.contact_id', 'item.contact_id', 'contact_key'];
  occurrences integer;
  replaced_count integer;
  from_contacts text;
  prefix text;
  trusted_owner name;
BEGIN
  FOR candidate IN SELECT * FROM (VALUES
    ('single', 'app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)', 4),
    ('contact', 'app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)', 1),
    ('apply', 'app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)', 1),
    ('mixed', 'app_private.confirm_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb)', 1),
    ('mixed_entry', 'app_private.confirm_personal_merge_mixed_resolutions_v2(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb,jsonb)', 1)
  ) AS functions(kind, signature, expected_count)
  LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc WHERE oid = candidate.signature::regprocedure;
    source := original.prosrc;
    replaced_count := 0;
    FOREACH alias IN ARRAY aliases LOOP
      old_key := format('octet_length(%s)::text || '':'' || %s', alias, alias);
      occurrences := (length(source) - length(replace(source, old_key, ''))) / length(old_key);
      replaced_count := replaced_count + occurrences;
      source := replace(source, old_key, format('app_private.personal_merge_contact_child_key_v1(%s)', alias));
    END LOOP;
    IF replaced_count <> candidate.expected_count THEN
      RAISE EXCEPTION '0160 bounded command anchors unavailable for %', candidate.signature;
    END IF;

    IF candidate.kind <> 'apply' THEN
      from_contacts := CASE WHEN candidate.kind IN ('mixed', 'mixed_entry')
        THEN 'FROM unnest(prelocked_contacts) AS contacts(contact_id)'
        ELSE 'FROM unnest(prelocked_contacts) contacts(contact_id)' END;
      prefix := CASE WHEN candidate.kind = 'single' THEN
        $prefix$'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'$prefix$
        ELSE $prefix$'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':current:'$prefix$ END;
      -- Old v1 aliases still reserve a command; prelock both before the generation fence.
      replacement := from_contacts || E'\n    UNION ALL\n    SELECT ' || prefix
        || E'\n      || octet_length(contact_id)::text || '':'' || contact_id '
        || from_contacts || E'\n    WHERE octet_length(contact_id) > 2048';
      IF length(source) - length(replace(source, from_contacts, '')) <> length(from_contacts) THEN
        RAISE EXCEPTION '0160 legacy command prelock anchor unavailable for %', candidate.signature;
      END IF;
      source := replace(source, from_contacts, replacement);
    END IF;

    IF candidate.kind = 'single' THEN
      anchor := $anchor$command.command_id =
          'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
          || app_private.personal_merge_contact_child_key_v1(pending.contact_id)$anchor$;
      replacement := $replacement$command.command_id IN (
          'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
            || app_private.personal_merge_contact_child_key_v1(pending.contact_id),
          'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
            || octet_length(pending.contact_id)::text || ':' || pending.contact_id)$replacement$;
      IF length(source) - length(replace(source, anchor, '')) <> length(anchor) THEN
        RAISE EXCEPTION '0160 legacy single-contact command conflict anchor unavailable';
      END IF;
      source := replace(source, anchor, replacement);
    END IF;

    EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, source);
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc' AND changed.prosrc = source) THEN
      RAISE EXCEPTION '0160 bounded command changed metadata or unrelated implementation for %', candidate.signature;
    END IF;
  END LOOP;

  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.personal_merge_contact_resolution_proof_v1(uuid,uuid)'::regprocedure;
  anchor := $anchor$      OR current_item.child_command_id <> 'personal-merge-contact-resolve-v1:' || requested_request_id::text
        || ':current:' || octet_length(current_item.contact_id)::text || ':' || current_item.contact_id$anchor$;
  -- Completed v1 receipts, including compressible long IDs, retain their exact proof.
  replacement := $replacement$      OR current_item.child_command_id NOT IN (
        'personal-merge-contact-resolve-v1:' || requested_request_id::text
          || ':current:' || octet_length(current_item.contact_id)::text || ':' || current_item.contact_id,
        'personal-merge-contact-resolve-v1:' || requested_request_id::text
          || ':current:' || app_private.personal_merge_contact_child_key_v1(current_item.contact_id))$replacement$;
  IF length(original.prosrc) - length(replace(original.prosrc, anchor, '')) <> length(anchor) THEN
    RAISE EXCEPTION '0160 completed current command proof anchor unavailable';
  END IF;
  source := replace(original.prosrc, anchor, replacement);
  EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, source);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed WHERE changed.oid = original.oid
    AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc' AND changed.prosrc = source) THEN
    RAISE EXCEPTION '0160 bounded command proof changed metadata or unrelated implementation';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.personal_merge_contact_child_key_v1(text) OWNER TO %I', trusted_owner);
END
$bounded_commands$;
