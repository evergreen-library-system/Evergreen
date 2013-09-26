BEGIN;

SELECT evergreen.upgrade_deps_block_check('0836', :eg_version);

CREATE TABLE config.floating_group (
    id      SERIAL PRIMARY KEY, 
    name    TEXT UNIQUE NOT NULL,
    manual  BOOL NOT NULL DEFAULT FALSE
    );

CREATE TABLE config.floating_group_member (
    id              SERIAL PRIMARY KEY,
    floating_group  INT NOT NULL REFERENCES config.floating_group (id),
    org_unit        INT NOT NULL REFERENCES actor.org_unit (id),
    stop_depth      INT NOT NULL DEFAULT 0,
    max_depth       INT,
    exclude         BOOL NOT NULL DEFAULT FALSE
    );

CREATE OR REPLACE FUNCTION evergreen.can_float( copy_floating_group integer, from_ou integer, to_ou integer ) RETURNS BOOL AS $f$
DECLARE
    float_member config.floating_group_member%ROWTYPE;
    shared_ou_depth INT;
    to_ou_depth INT;
BEGIN
    -- Grab the shared OU depth. If this is less than the stop depth later we ignore the entry.
    SELECT INTO shared_ou_depth max(depth) FROM actor.org_unit_common_ancestors( from_ou, to_ou ) aou JOIN actor.org_unit_type aout ON aou.ou_type = aout.id;
    -- Grab the to ou depth. If this is greater than max depth we ignore the entry.
    SELECT INTO to_ou_depth depth FROM actor.org_unit aou JOIN actor.org_unit_type aout ON aou.ou_type = aout.id WHERE aou.id = to_ou;
    -- Grab float members that apply. We don't care what we get beyond wanting excluded ones first.
    SELECT INTO float_member *
        FROM
            config.floating_group_member cfgm
            JOIN actor.org_unit aou ON cfgm.org_unit = aou.id
            JOIN actor.org_unit_type aout ON aou.ou_type = aout.id
        WHERE
            cfgm.floating_group = copy_floating_group
            AND to_ou IN (SELECT id FROM actor.org_unit_descendants(aou.id))
            AND cfgm.stop_depth <= shared_ou_depth
            AND (cfgm.max_depth IS NULL OR to_ou_depth <= max_depth)
        ORDER BY
            exclude DESC;
    -- If we found something then we want to return the opposite of the exclude flag
    IF FOUND THEN
        RETURN NOT float_member.exclude;
    END IF;
    -- Otherwise no floating.
    RETURN false;
END;
$f$ LANGUAGE PLPGSQL;

INSERT INTO config.floating_group(name) VALUES ('Everywhere');
INSERT INTO config.floating_group_member(floating_group, org_unit) VALUES (1, 1);

-- We need to drop these before we can update asset.copy
DROP VIEW auditor.asset_copy_lifecycle;
DROP VIEW auditor.serial_unit_lifecycle;

-- Update the appropriate auditor tables
ALTER TABLE auditor.asset_copy_history
    ALTER COLUMN floating DROP DEFAULT,
    ALTER COLUMN floating DROP NOT NULL,
    ALTER COLUMN floating TYPE int USING CASE WHEN floating THEN 1 ELSE NULL END;
ALTER TABLE auditor.serial_unit_history
    ALTER COLUMN floating DROP DEFAULT,
    ALTER COLUMN floating DROP NOT NULL,
    ALTER COLUMN floating TYPE int USING CASE WHEN floating THEN 1 ELSE NULL END;

-- Update asset.copy itself (does not appear to trigger update triggers!)
ALTER TABLE asset.copy
    ALTER COLUMN floating DROP DEFAULT,
    ALTER COLUMN floating DROP NOT NULL,
    ALTER COLUMN floating TYPE int USING CASE WHEN floating THEN 1 ELSE NULL END;

ALTER TABLE asset.copy ADD CONSTRAINT asset_copy_floating_fkey FOREIGN KEY (floating) REFERENCES config.floating_group (id) DEFERRABLE INITIALLY DEFERRED;

-- Update asset.copy_template too
ALTER TABLE asset.copy_template
    ALTER COLUMN floating TYPE int USING CASE WHEN floating THEN 1 ELSE NULL END;
ALTER TABLE asset.copy_template ADD CONSTRAINT asset_copy_template_floating_fkey FOREIGN KEY (floating) REFERENCES config.floating_group (id) DEFERRABLE INITIALLY DEFERRED;

INSERT INTO permission.perm_list( code, description) VALUES
('ADMIN_FLOAT_GROUPS', 'Allows administration of floating groups');

-- And lets just update all auditors to re-create those lifecycle views
SELECT auditor.update_auditors();

COMMIT;
