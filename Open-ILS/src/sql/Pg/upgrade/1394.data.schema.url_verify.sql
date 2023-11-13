
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1394', :eg_version);

ALTER TABLE url_verify.url_selector
    DROP CONSTRAINT url_selector_session_fkey,
    ADD CONSTRAINT url_selector_session_fkey 
        FOREIGN KEY (session) 
        REFERENCES url_verify.session(id) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE url_verify.url
    DROP CONSTRAINT url_session_fkey,
    DROP CONSTRAINT url_redirect_from_fkey,
    ADD CONSTRAINT url_session_fkey 
        FOREIGN KEY (session) 
        REFERENCES url_verify.session(id) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT url_redirect_from_fkey
        FOREIGN KEY (redirect_from)
        REFERENCES url_verify.url(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE url_verify.verification_attempt
    DROP CONSTRAINT verification_attempt_session_fkey,
    ADD CONSTRAINT verification_attempt_session_fkey 
        FOREIGN KEY (session) 
        REFERENCES url_verify.session(id) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE url_verify.url_verification
    DROP CONSTRAINT url_verification_url_fkey,
    ADD CONSTRAINT url_verification_url_fkey
        FOREIGN KEY (url)
        REFERENCES url_verify.url(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.link_checker', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.link_checker',
        'Grid Config: catalog.link_checker',
        'cwst', 'label'
    )
), (
    'eg.grid.catalog.link_checker.attempt', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.link_checker.attempt',
        'Grid Config: catalog.link_checker.attempt',
        'cwst', 'label'
    )
), (
    'eg.grid.catalog.link_checker.url', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.link_checker.url',
        'Grid Config: catalog.link_checker.url',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.link_checker', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.link_checker',
        'Grid Filter Sets: catalog.link_checker',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.link_checker.attempt', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.link_checker.attempt',
        'Grid Filter Sets: catalog.link_checker.attempt',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.link_checker.url', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.link_checker.url',
        'Grid Filter Sets: catalog.link_checker.url',
        'cwst', 'label'
    )
);

COMMIT;
