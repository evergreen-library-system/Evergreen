BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0044');

INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.claim_never_checked_out.mark_missing',
        'Claim Never Checked Out: Mark copy as missing', 
        'When a circ is marked as claims-never-checked-out, mark the copy as missing',
        'bool'
    );


COMMIT;
