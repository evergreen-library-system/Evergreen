BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

CREATE TABLE config.patron_loader_header_map (
    id SERIAL,
    org_unit INTEGER NOT NULL,
    import_header TEXT NOT NULL,
    default_header TEXT NOT NULL
);
ALTER TABLE config.patron_loader_header_map ADD CONSTRAINT config_patron_loader_header_map_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE config.patron_loader_value_map (
    id SERIAL,
    org_unit INTEGER NOT NULL,
    mapping_type TEXT NOT NULL,
    import_value TEXT NOT NULL,
    native_value TEXT NOT NULL
);
ALTER TABLE config.patron_loader_value_map ADD CONSTRAINT config_patron_loader_value_map_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE actor.patron_loader_log (
    id SERIAL,
    session BIGINT,
    org_unit INTEGER NOT NULL,
    event TEXT,
    record_count INTEGER,
    logtime TIMESTAMP DEFAULT NOW()
);
ALTER TABLE actor.patron_loader_log ADD CONSTRAINT actor_patron_loader_log_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;
