BEGIN;

SELECT evergreen.upgrade_deps_block_check('1062', :eg_version);

CREATE TABLE acq.edi_attr (
    key     TEXT PRIMARY KEY,
    label   TEXT NOT NULL UNIQUE
);

CREATE TABLE acq.edi_attr_set (
    id      SERIAL  PRIMARY KEY,
    label   TEXT NOT NULL UNIQUE
);

CREATE TABLE acq.edi_attr_set_map (
    id          SERIAL  PRIMARY KEY,
    attr_set    INTEGER NOT NULL REFERENCES acq.edi_attr_set(id) 
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    attr        TEXT NOT NULL REFERENCES acq.edi_attr(key) 
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT edi_attr_set_map_attr_once UNIQUE (attr_set, attr)
);

-- An attr_set is not strictly required, since some edi_accounts/vendors 
-- may not need to apply any attributes.
ALTER TABLE acq.edi_account 
    ADD COLUMN attr_set INTEGER REFERENCES acq.edi_attr_set(id),
    ADD COLUMN use_attrs BOOLEAN NOT NULL DEFAULT FALSE;

COMMIT;


