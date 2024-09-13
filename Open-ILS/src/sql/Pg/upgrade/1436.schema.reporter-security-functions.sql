BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1436', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.direct_opt_in_check(
    patron_id   INT,
    staff_id    INT, -- patron must be opted in (directly or implicitly) to one of the staff's working locations
    permlist    TEXT[] DEFAULT '{}'::TEXT[] -- if passed, staff must ADDITIONALLY possess at least one of these permissions at an opted-in location
) RETURNS BOOLEAN AS $f$
DECLARE
    default_boundary    INT;
    org_depth           INT;
    patron              actor.usr%ROWTYPE;
    staff               actor.usr%ROWTYPE;
    patron_visible_at   INT[];
    patron_hard_wall    INT[];
    staff_orgs          INT[];
    current_staff_org   INT;
    passed_optin        BOOL;
BEGIN
    passed_optin := FALSE;

    SELECT * INTO patron FROM actor.usr WHERE id = patron_id;
    SELECT * INTO staff FROM actor.usr WHERE id = staff_id;

    IF patron.id IS NULL OR staff.id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- get the hard wall, if any
    SELECT oils_json_to_text(value)::INT INTO default_boundary
      FROM actor.org_unit_ancestor_setting('org.restrict_opt_to_depth', patron.home_ou);

    IF default_boundary IS NULL THEN default_boundary := 0; END IF;

    IF default_boundary = 0 THEN -- common case
        SELECT ARRAY_AGG(id) INTO patron_hard_wall FROM actor.org_unit;
    ELSE
        -- Patron opt-in scope(s), including home_ou from default_boundary depth
        SELECT  ARRAY_AGG(id) INTO patron_hard_wall
          FROM  actor.org_unit_descendants(patron.home_ou, default_boundary);
    END IF;

    -- gather where the patron has opted in, and their home
    SELECT  COALESCE(ARRAY_AGG(DISTINCT aoud.id),'{}') INTO patron_visible_at
      FROM  actor.usr_org_unit_opt_in auoi
            JOIN LATERAL actor.org_unit_descendants(auoi.org_unit) aoud ON TRUE
      WHERE auoi.usr = patron.id;

    patron_visible_at := patron_visible_at || patron.home_ou;

    <<staff_org_loop>>
    FOR current_staff_org IN SELECT work_ou FROM permission.usr_work_ou_map WHERE usr = staff.id LOOP

        SELECT oils_json_to_text(value)::INT INTO org_depth
          FROM actor.org_unit_ancestor_setting('org.patron_opt_boundary', current_staff_org);

        IF FOUND THEN
            SELECT ARRAY_AGG(DISTINCT id) INTO staff_orgs FROM actor.org_unit_descendants(current_staff_org,org_depth);
        ELSE
            SELECT ARRAY_AGG(DISTINCT id) INTO staff_orgs FROM actor.org_unit_descendants(current_staff_org);
        END IF;

        -- If this staff org (adjusted) isn't at least partly inside the allowed range, move on.
        IF NOT (staff_orgs && patron_hard_wall) THEN CONTINUE staff_org_loop; END IF;

        -- If this staff org (adjusted) overlaps with the patron visibility list
        IF staff_orgs && patron_visible_at THEN passed_optin := TRUE; EXIT staff_org_loop; END IF;

    END LOOP staff_org_loop;

    -- does the staff member have a requested permission where the patron lives or has opted in?
    IF passed_optin AND cardinality(permlist) > 0 THEN
        SELECT  ARRAY_AGG(id) INTO staff_orgs
          FROM  UNNEST(permlist) perms (p)
                JOIN LATERAL permission.usr_has_perm_at_all(staff.id, perms.p) perms_at (id) ON TRUE;

        passed_optin := COALESCE(staff_orgs && patron_visible_at, FALSE);
    END IF;

    RETURN passed_optin;

END;
$f$ STABLE LANGUAGE PLPGSQL;

-- This function defaults to RESTRICTING access to data if applied to
-- a table/class that it does not explicitly know how to handle.
CREATE OR REPLACE FUNCTION evergreen.hint_opt_in_check(
    hint_val    TEXT,
    pkey_val    BIGINT, -- pkey value of the hinted row
    staff_id    INT,
    permlist    TEXT[] DEFAULT '{}'::TEXT[] -- if passed, staff must ADDITIONALLY possess at least one of these permissions at an opted-in location
) RETURNS BOOLEAN AS $f$
BEGIN
    CASE hint_val
        WHEN 'aua' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_address WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'auact' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_activity WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'aus' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_setting WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'actscecm' THEN
            RETURN evergreen.direct_opt_in_check((SELECT target_usr FROM actor.stat_cat_entry_usr_map WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'ateo' THEN
            RETURN evergreen.direct_opt_in_check(
                (SELECT e.context_user FROM action_trigger.event e JOIN action_trigger.event_output eo ON (eo.event = e.id) WHERE eo.id = pkey_val LIMIT 1),
                staff_id,
                permlist
            );
        ELSE
            RETURN FALSE;
    END CASE;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.redact_value(
    input_data      anycompatible,
    skip_redaction  BOOLEAN         DEFAULT FALSE,  -- pass TRUE for "I passed the test!" and avoid redaction
    redact_with     anycompatible   DEFAULT NULL
) RETURNS anycompatible AS $f$
DECLARE
    result ALIAS FOR $0;
BEGIN
    IF skip_redaction THEN
        result := input_data;
    ELSE
        result := redact_with;
    END IF;

    RETURN result;
END;
$f$ STABLE LANGUAGE PLPGSQL;

COMMIT;

