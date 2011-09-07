BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


CREATE TABLE config.org_unit_setting_type_log (
    id              BIGSERIAL   PRIMARY KEY,
    date_applied    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    org             INT         REFERENCES actor.org_unit (id),
    original_value  TEXT,
    new_value       TEXT,
    field_name      TEXT      REFERENCES config.org_unit_setting_type (name)
);

COMMIT;
