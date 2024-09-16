-- Add bib bucket related columns to reporter.schedule

BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE reporter.schedule ADD COLUMN new_record_bucket BOOL NOT NULL DEFAULT 'false';
ALTER TABLE reporter.schedule ADD COLUMN existing_record_bucket BOOL NOT NULL DEFAULT 'false';

CREATE TABLE container.biblio_record_entry_bucket_shares (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    share_org   INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT brebs_org_once_per_bucket UNIQUE (bucket, share_org)
);

CREATE TYPE container.usr_flag_type AS ENUM ('favorite');
CREATE TABLE container.biblio_record_entry_bucket_usr_flags (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    usr         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    flag        container.usr_flag_type NOT NULL DEFAULT 'favorite',
    CONSTRAINT brebs_flag_once_per_usr_per_bucket UNIQUE (bucket, usr, flag)
);

COMMIT;
