BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES (
    695, 'DELETE_INACTIVE_NONPRIMARY_PATRON_CARD',
    oils_i18n_gettext(
        695,
        'Allow a user to delete a patron''s inactive, non-primary cards',
        'ppl',
        'description'
    )
);

COMMIT;
