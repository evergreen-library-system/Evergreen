BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0344');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) 
    VALUES (
        'circ.selfcheck.block_checkout_on_copy_status',
        oils_i18n_gettext(
            'circ.selfcheck.block_checkout_on_copy_status',
            'Selfcheck: Block copy checkout status',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.selfcheck.block_checkout_on_copy_status',
            'List of copy status IDs that will block checkout even if the generic COPY_NOT_AVAILABLE event is overridden',
            'coust',
            'description'
        ),
        'array'
    );

COMMIT;
