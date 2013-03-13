
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0771', :eg_version);

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'au.barred',
        'au',
        'A user was barred by staff',
        FALSE
    );

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'au.unbarred',
        'au',
        'A user was un-barred by staff',
        FALSE
    );

INSERT INTO action_trigger.validator (
        module, 
        description
    ) VALUES (
        'PatronBarred',
        'Tests if a patron is currently marked as barred'
    );

INSERT INTO action_trigger.validator (
        module, 
        description
    ) VALUES (
        'PatronNotBarred',
        'Tests if a patron is currently not marked as barred'
    );

COMMIT;
