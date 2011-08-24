-- Evergreen DB patch XXXX.data.acq-copy-creator-from-receiver.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE acq.lineitem_detail 
    ADD COLUMN receiver	INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;


COMMIT;
