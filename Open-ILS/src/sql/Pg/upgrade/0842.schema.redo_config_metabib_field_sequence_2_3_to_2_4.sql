BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0842', :eg_version);

-- this upgrade is only for people coming from 2_3, and is a NO-OP for those on 2_4
ALTER TABLE config.metabib_field_ts_map DROP CONSTRAINT metabib_field_ts_map_metabib_field_fkey;

ALTER TABLE config.metabib_field_ts_map ADD CONSTRAINT metabib_field_ts_map_metabib_field_fkey FOREIGN KEY (metabib_field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
