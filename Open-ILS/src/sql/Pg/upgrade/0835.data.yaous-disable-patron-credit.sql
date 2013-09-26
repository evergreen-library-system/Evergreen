BEGIN;

SELECT evergreen.upgrade_deps_block_check('0835', :eg_version);

INSERT INTO config.org_unit_setting_type 
    (grp, name, datatype, label, description) 
VALUES (
    'finance',
    'circ.disable_patron_credit',
    'bool',
    oils_i18n_gettext(
        'circ.disable_patron_credit',
        'Disable Patron Credit',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.disable_patron_credit',
        'Do not allow patrons to accrue credit or pay fines/fees with accrued credit',
        'coust',
        'description'
    )
);

COMMIT;
