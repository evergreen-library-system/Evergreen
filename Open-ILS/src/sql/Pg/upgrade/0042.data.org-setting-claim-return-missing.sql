BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0042');

INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.claim_return.mark_missing',
        'Claim Return: Mark copy as missing', 
        'When a circ is marked as claims-returned, also mark the copy as missing',
        'bool'
    );


COMMIT;
