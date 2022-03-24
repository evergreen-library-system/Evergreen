BEGIN;

SELECT evergreen.upgrade_deps_block_check('1315', :eg_version);

CREATE TABLE config.ui_staff_portal_page_entry_type (
    code        TEXT PRIMARY KEY,
    label       TEXT NOT NULL
);

INSERT INTO config.ui_staff_portal_page_entry_type (code, label)
VALUES
    ('link', oils_i18n_gettext('link', 'Link', 'cusppet', 'label')),
    ('menuitem', oils_i18n_gettext('menuitem', 'Menu Item', 'cusppet', 'label')),
    ('text', oils_i18n_gettext('text', 'Text and/or HTML', 'cusppet', 'label')),
    ('header', oils_i18n_gettext('header', 'Header', 'cusppet', 'label')),
    ('catalogsearch', oils_i18n_gettext('catalogsearch', 'Catalog Search Box', 'cusppet', 'label'));


CREATE TABLE config.ui_staff_portal_page_entry (
    id          SERIAL PRIMARY KEY,
    page_col    INTEGER NOT NULL,
    col_pos     INTEGER NOT NULL,
    entry_type  TEXT NOT NULL, -- REFERENCES config.ui_staff_portal_page_entry_type(code)
    label       TEXT,
    image_url   TEXT,
    target_url  TEXT,
    entry_text  TEXT,
    owner       INT NOT NULL -- REFERENCES actor.org_unit (id)
);

ALTER TABLE config.ui_staff_portal_page_entry ADD CONSTRAINT cusppe_entry_type_fkey
    FOREIGN KEY (entry_type) REFERENCES  config.ui_staff_portal_page_entry_type(code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.ui_staff_portal_page_entry ADD CONSTRAINT cusppe_owner_fkey
    FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
