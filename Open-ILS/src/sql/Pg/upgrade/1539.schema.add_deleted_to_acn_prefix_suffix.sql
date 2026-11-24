BEGIN;

SELECT evergreen.upgrade_deps_block_check('1539', :eg_version);

ALTER TABLE asset.call_number_suffix ADD COLUMN IF NOT EXISTS deleted BOOLEAN DEFAULT FALSE;
ALTER TABLE asset.call_number_prefix ADD COLUMN IF NOT EXISTS deleted BOOLEAN DEFAULT FALSE;

CREATE OR REPLACE FUNCTION asset.check_delete_call_number_prefix(acnp_id integer)
  RETURNS void
  AS $function$
BEGIN
PERFORM TRUE FROM asset.call_number WHERE prefix = acnp_id AND NOT deleted LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Call Number Prefix % is used in active call numbers and cannot be deleted', acnp_id;
    END IF;

    IF acnp_id = -1 THEN
        RAISE EXCEPTION
            'Call number prefix -1 cannot be deleted';
    END IF;
END;

$function$ LANGUAGE plpgsql;

CREATE OR REPLACE RULE protect_acn_prefix_delete AS
    ON DELETE TO asset.call_number_prefix DO INSTEAD (
        UPDATE asset.call_number_prefix SET deleted = TRUE WHERE OLD.id = asset.call_number_prefix.id;
        SELECT asset.check_delete_call_number_prefix(OLD.id) AS check_delete_call_number_prefix;
    );

CREATE OR REPLACE FUNCTION asset.check_delete_call_number_suffix(acns_id integer)
  RETURNS void
  AS $function$
BEGIN
PERFORM TRUE FROM asset.call_number WHERE suffix = acns_id AND NOT deleted LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Call Number Suffix % is used in active call numbers and cannot be deleted', acns_id;
    END IF;

    IF acns_id = -1 THEN
        RAISE EXCEPTION
            'Call number suffix -1 cannot be deleted';
    END IF;
END;

$function$ LANGUAGE plpgsql;

CREATE OR REPLACE RULE protect_acn_suffix_delete AS
    ON DELETE TO asset.call_number_suffix DO INSTEAD (
        UPDATE asset.call_number_suffix SET deleted = TRUE WHERE OLD.id = asset.call_number_suffix.id;
        SELECT asset.check_delete_call_number_suffix(OLD.id) AS check_delete_call_number_suffix;
    );

COMMIT;
