
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0714', :eg_version);

INSERT into config.org_unit_setting_type 
    (name, grp, label, description, datatype) 
    VALUES ( 
        'opac.patron.auto_overide_hold_events', 
        'opac',
        oils_i18n_gettext(
            'opac.patron.auto_overide_hold_events',
            'Auto-Override Permitted Hold Blocks (Patrons)',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.patron.auto_overide_hold_events',
            'When a patron places a hold that fails and the patron has the correct permission ' ||
            'to override the hold, automatically override the hold without presenting a message ' ||
            'to the patron and requiring that the patron make a decision to override',
            'coust', 
            'description'
        ),
        'bool'
    );

COMMIT;
