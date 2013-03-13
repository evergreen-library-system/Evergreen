
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0775', :eg_version);

ALTER TABLE config.z3950_attr
    DROP CONSTRAINT z3950_attr_source_fkey,
    ADD CONSTRAINT z3950_attr_source_fkey 
        FOREIGN KEY (source) 
        REFERENCES config.z3950_source(name) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

COMMIT;
