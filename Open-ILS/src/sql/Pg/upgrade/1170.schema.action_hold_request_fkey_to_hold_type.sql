BEGIN;

SELECT evergreen.upgrade_deps_block_check('1170', :eg_version);

CREATE TABLE config.hold_type (
    id          SERIAL,
    hold_type   TEXT UNIQUE,
    description TEXT
);

INSERT INTO config.hold_type (hold_type,description) VALUES
    ('C','Copy Hold'),
    ('V','Volume Hold'),
    ('T','Title Hold'),
    ('M','Metarecord Hold'),
    ('R','Recall Hold'),
    ('F','Force Hold'),
    ('I','Issuance Hold'),
    ('P','Part Hold')
;

ALTER TABLE action.hold_request ADD CONSTRAINT hold_request_hold_type_fkey FOREIGN KEY (hold_type) REFERENCES config.hold_type(hold_type) DEFERRABLE INITIALLY DEFERRED;

COMMIT;
