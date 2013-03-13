BEGIN;

SELECT evergreen.upgrade_deps_block_check('0779', :eg_version);

CREATE TABLE vandelay.import_bib_trash_group(
    id SERIAL PRIMARY KEY,
    owner INT NOT NULL REFERENCES actor.org_unit(id),
    label TEXT NOT NULL, --i18n
    always_apply BOOLEAN NOT NULL DEFAULT FALSE,
	CONSTRAINT vand_import_bib_trash_grp_owner_label UNIQUE (owner, label)
);

-- otherwise, the ALTER TABLE statement below
-- will fail with pending trigger events.
SET CONSTRAINTS ALL IMMEDIATE;

ALTER TABLE vandelay.import_bib_trash_fields
    -- allow null-able for now..
    ADD COLUMN grp INTEGER REFERENCES vandelay.import_bib_trash_group;

-- add any existing trash_fields to "Legacy" groups (one per unique field
-- owner) as part of the upgrade, since grp is now required.
-- note that vandelay.import_bib_trash_fields was never used before,
-- so in most cases this should be a no-op.

INSERT INTO vandelay.import_bib_trash_group (owner, label)
    SELECT DISTINCT(owner), 'Legacy' FROM vandelay.import_bib_trash_fields;

UPDATE vandelay.import_bib_trash_fields field SET grp = tgroup.id
    FROM vandelay.import_bib_trash_group tgroup
    WHERE tgroup.owner = field.owner;
    
ALTER TABLE vandelay.import_bib_trash_fields
    -- now that have values, we can make this non-null
    ALTER COLUMN grp SET NOT NULL,
    -- drop outdated constraint
    DROP CONSTRAINT vand_import_bib_trash_fields_idx,
    -- owner is implied by the grp
    DROP COLUMN owner, 
    -- make grp+field unique
    ADD CONSTRAINT vand_import_bib_trash_fields_once_per UNIQUE (grp, field);

COMMIT;
