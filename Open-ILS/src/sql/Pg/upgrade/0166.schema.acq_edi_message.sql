BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0166');

CREATE TABLE acq.edi_message (
    id               SERIAL          PRIMARY KEY,
    account          INTEGER         REFERENCES acq.edi_account(id)
                                     DEFERRABLE INITIALLY DEFERRED,
    remote_file      TEXT,
    create_time      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    translate_time   TIMESTAMPTZ,
    process_time     TIMESTAMPTZ,
    error_time       TIMESTAMPTZ,
    status           TEXT            NOT NULL DEFAULT 'new'
                                     CONSTRAINT status_value CHECK
                                     ( status IN (
                                        'new',          -- needs to be translated
                                        'translated',   -- needs to be processed
                                        'trans_error',  -- error in translation step
                                        'processed',    -- needs to have remote_file deleted
                                        'proc_error',   -- error in processing step
                                        'delete_error', -- error in deletion
                                        'complete'      -- done
                                     )),
    edi              TEXT,
    jedi             TEXT,
    error            TEXT
);

ALTER TABLE actor.org_address ADD COLUMN san TEXT;

COMMIT;
