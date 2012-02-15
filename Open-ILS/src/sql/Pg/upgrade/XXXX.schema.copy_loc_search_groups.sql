BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE asset.copy_location_group (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL, -- i18n
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    pos             INT     NOT NULL DEFAULT 0,
    opac_visible    BOOL    NOT NULL DEFAULT TRUE,
    CONSTRAINT lgroup_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE asset.copy_location_group_map (
    id       SERIAL PRIMARY KEY,
    location    INT     NOT NULL REFERENCES asset.copy_location (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    lgroup      INT     NOT NULL REFERENCES asset.copy_location_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT  lgroup_once_per_group UNIQUE (lgroup,location)
);

COMMIT;

/* UNDO
BEGIN;
DROP TABLE asset.copy_location_group_map;
DROP TABLE asset.copy_location_group;
COMMIT;
*/

