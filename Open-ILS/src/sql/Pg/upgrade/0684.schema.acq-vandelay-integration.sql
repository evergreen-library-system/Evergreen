-- Evergreen DB patch 0684.schema.acq-vandelay-integration.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0684', :eg_version);

-- schema --

-- Replace the constraints with more flexible ENUM's
ALTER TABLE vandelay.queue DROP CONSTRAINT queue_queue_type_check;
ALTER TABLE vandelay.bib_queue DROP CONSTRAINT bib_queue_queue_type_check;
ALTER TABLE vandelay.authority_queue DROP CONSTRAINT authority_queue_queue_type_check;

CREATE TYPE vandelay.bib_queue_queue_type AS ENUM ('bib', 'acq');
CREATE TYPE vandelay.authority_queue_queue_type AS ENUM ('authority');

-- dropped column is also implemented by the child tables
ALTER TABLE vandelay.queue DROP COLUMN queue_type; 

-- to recover after using the undo sql from below
-- alter table vandelay.bib_queue  add column queue_type text default 'bib' not null;
-- alter table vandelay.authority_queue  add column queue_type text default 'authority' not null;

-- modify the child tables to use the ENUMs
ALTER TABLE vandelay.bib_queue 
    ALTER COLUMN queue_type DROP DEFAULT,
    ALTER COLUMN queue_type TYPE vandelay.bib_queue_queue_type 
        USING (queue_type::vandelay.bib_queue_queue_type),
    ALTER COLUMN queue_type SET DEFAULT 'bib';

ALTER TABLE vandelay.authority_queue 
    ALTER COLUMN queue_type DROP DEFAULT,
    ALTER COLUMN queue_type TYPE vandelay.authority_queue_queue_type 
        USING (queue_type::vandelay.authority_queue_queue_type),
    ALTER COLUMN queue_type SET DEFAULT 'authority';

-- give lineitems a pointer to their vandelay queued_record

ALTER TABLE acq.lineitem ADD COLUMN queued_record BIGINT
    REFERENCES vandelay.queued_bib_record (id) 
    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.acq_lineitem_history ADD COLUMN queued_record BIGINT
    REFERENCES vandelay.queued_bib_record (id) 
    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- seed data --

INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 
        521, 
        'IMPORT_ACQ_LINEITEM_BIB_RECORD_UPLOAD', 
        oils_i18n_gettext( 
            521,
            'Allows a user to create new bibs directly from an ACQ MARC file upload', 
            'ppl', 
            'description' 
        )
    );


INSERT INTO vandelay.import_error ( code, description ) 
    VALUES ( 
        'import.record.perm_failure', 
        oils_i18n_gettext(
            'import.record.perm_failure', 
            'Perm failure creating a record', 'vie', 'description') 
    );


COMMIT;

/* UNDO SQL
-- XXX this does not exactly recover the state.  The bib/auth queue_type colum is
-- directly inherited instead of overridden, which will fail with some of the sql above.
ALTER TABLE acq.lineitem DROP COLUMN queued_record;
ALTER TABLE acq.acq_lineitem_history DROP COLUMN queued_record;
ALTER TABLE vandelay.authority_queue DROP COLUMN queue_type;
ALTER TABLE vandelay.bib_queue DROP COLUMN queue_type;

DROP TYPE vandelay.bib_queue_queue_type;
DROP TYPE vandelay.authority_queue_queue_type;

ALTER TABLE vandelay.bib_queue DROP CONSTRAINT vand_bib_queue_name_once_per_owner_const;
ALTER TABLE vandelay.authority_queue DROP CONSTRAINT vand_authority_queue_name_once_per_owner_const;

ALTER TABLE vandelay.queue ADD COLUMN queue_type TEXT NOT NULL DEFAULT 'bib' CHECK (queue_type IN ('bib','authority'));
UPDATE vandelay.authority_queue SET queue_type = 'authority';
ALTER TABLE vandelay.bib_queue ADD CONSTRAINT bib_queue_queue_type_check CHECK (queue_type IN ('bib'));
ALTER TABLE vandelay.authority_queue ADD CONSTRAINT authority_queue_queue_type_check CHECK (queue_type IN ('authority'));

DELETE FROM permission.perm_list WHERE code = 'IMPORT_ACQ_LINEITEM_BIB_RECORD_UPLOAD';
DELETE FROM vandelay.import_error WHERE code = 'import.record.perm_failure';
*/


