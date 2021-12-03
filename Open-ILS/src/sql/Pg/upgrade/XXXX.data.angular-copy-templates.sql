BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

DO $SQL$
BEGIN
    
    PERFORM TRUE FROM config.usr_setting_type WHERE name = 'cat.copy.templates';

    IF NOT FOUND THEN -- no matching user setting

        PERFORM TRUE FROM config.workstation_setting_type WHERE name = 'cat.copy.templates';

        IF NOT FOUND THEN
            -- no matching workstation setting
            -- Migrate the existing user setting and its data to the new name.

            UPDATE config.usr_setting_type 
            SET name = 'cat.copy.templates' 
            WHERE name = 'webstaff.cat.copy.templates';

            UPDATE actor.usr_setting
            SET name = 'cat.copy.templates' 
            WHERE name = 'webstaff.cat.copy.templates';

        END IF;
    END IF;

END; 
$SQL$;

COMMIT;

