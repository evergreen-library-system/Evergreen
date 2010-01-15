BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0133'); -- atz

CREATE TABLE config.remote_account (
    id          SERIAL  PRIMARY KEY,
    label       TEXT    NOT NULL,
    host        TEXT    NOT NULL,   -- name or IP, :port optional
    username    TEXT,               -- optional, since we could default to $USER
    password    TEXT,               -- optional, since we could use SSH keys, or anonymous login.
    account     TEXT,               -- aka profile or FTP "account" command
    path        TEXT,               -- aka directory
    owner       INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    last_activity TIMESTAMP WITH TIME ZONE
);

CREATE TABLE acq.edi_account (      -- similar tables can extend remote_account for other parts of EG
    provider    INT     NOT NULL REFERENCES acq.provider          (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    in_dir      TEXT    -- incoming messages dir (probably different than config.remote_account.path, the outgoing dir)
) INHERITS (config.remote_account);

-- We need a UNIQUE constraint here also, to support the FK in the next command
ALTER TABLE acq.edi_account ADD CONSTRAINT acq_edi_account_id_unique UNIQUE (id);

-- null edi_default is OK... it has to be, since we have no values in acq.edi_account yet
ALTER TABLE acq.provider ADD COLUMN edi_default INT REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;
