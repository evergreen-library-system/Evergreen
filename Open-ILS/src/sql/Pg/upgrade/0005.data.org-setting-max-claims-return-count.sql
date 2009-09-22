BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0005');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.max_patron_claim_return_count',
    'Max Patron Claims Returned Count',
    'When this count is exceeded, a staff override is required to mark the item as claims returned',
    'integer'
);

COMMIT;

