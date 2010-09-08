BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0389'); -- miker

-- Making this a global_flag (UI accessible) instead of an internal_flag
INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.holds.empty_issuance_ok',
        oils_i18n_gettext(
            'circ.holds.empty_issuance_ok',
            'Holds: Allow holds on empty issuances',
            'cgf',
            'label'
        ),
        TRUE
    );

INSERT INTO permission.perm_list (code, description) VALUES ('ISSUANCE_HOLDS', 'Allow a user to place holds on serials issuances');

COMMIT;

