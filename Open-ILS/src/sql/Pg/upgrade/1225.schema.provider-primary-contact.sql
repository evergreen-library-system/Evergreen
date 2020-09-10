BEGIN;

SELECT evergreen.upgrade_deps_block_check('1225', :eg_version);

ALTER TABLE acq.provider ADD COLUMN primary_contact INT;
ALTER TABLE acq.provider ADD CONSTRAINT acq_provider_primary_contact_fkey FOREIGN KEY (primary_contact) REFERENCES acq.provider_contact (id) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
