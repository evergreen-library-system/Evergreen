BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

CREATE TABLE action.eresource_link_click (
    id          BIGSERIAL PRIMARY KEY,
    clicked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    url         TEXT,
    record      BIGINT NOT NULL REFERENCES biblio.record_entry (id)
);

CREATE TABLE action.eresource_link_click_course (
    id            SERIAL      PRIMARY KEY,
    click         BIGINT NOT NULL REFERENCES action.eresource_link_click (id) ON DELETE CASCADE,
    course        INT NOT NULL, -- no REFERENCES, since the course could have been deleted
    course_name   TEXT NOT NULL,
    course_number TEXT NOT NULL
);

INSERT INTO config.global_flag  (name, label, enabled)
    VALUES (
        'opac.eresources.link_click_tracking',
        oils_i18n_gettext('opac.eresources.link_click_tracking',
                          'Track clicks on eresources links.  Before enabling this global flag, be sure that you are monitoring disk space on your database server and have a cron job set up to delete click records after the desired retention interval.',
                          'cgf', 'label'),
        FALSE
    );

CREATE FUNCTION action.delete_old_eresource_link_clicks(days integer)
    RETURNS VOID AS
    'DELETE FROM action.eresource_link_click
     WHERE clicked_at < current_timestamp
               - ($1::text || '' days'')::interval'
    LANGUAGE SQL
    VOLATILE;

COMMIT;

