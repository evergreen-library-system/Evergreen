--Upgrade Script for 2.2.3 to 2.2.4
\set eg_version '''2.2.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0744', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.lost.xact_open_on_zero',
        'finance',
        oils_i18n_gettext(
            'circ.lost.xact_open_on_zero',
            'Leave transaction open when lost balance equals zero',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.lost.xact_open_on_zero',
            'Leave transaction open when lost balance equals zero.  This leaves the lost copy on the patron record when it is paid',
            'coust',
            'description'
        ),
        'bool'
    );


SELECT evergreen.upgrade_deps_block_check('0746', :eg_version);

ALTER TABLE action.hold_request ALTER COLUMN email_notify SET DEFAULT 'false';

COMMIT;
