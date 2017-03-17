BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX edi_message_remote_file_idx ON acq.edi_message (evergreen.lowercase(remote_file));

COMMIT;
