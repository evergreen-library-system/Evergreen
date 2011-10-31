-- Evergreen DB patch XXXX.data.vandelay-queue-bib-bucket-type.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO container.biblio_record_entry_bucket_type (code, label) VALUES (
    'vandelay_queue',
    oils_i18n_gettext('vandelay_queue', 'Vandelay Queue', 'cbrebt', 'label')
);

COMMIT;
