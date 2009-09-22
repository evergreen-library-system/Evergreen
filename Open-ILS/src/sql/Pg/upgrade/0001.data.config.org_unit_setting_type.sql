BEGIN;

-- Org Unit Settings for configuring org unit weights and org unit max-loops for hold targeting

INSERT INTO config.upgrade_log (version) VALUES ('0001');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.org_unit_target_weight',
    'Holds: Org Unit Target Weight',
    'Org Units can be organized into hold target groups based on a weight.  Potential copies from org units with the same weight are chosen at random.',
    'integer'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.target_holds_by_org_unit_weight',
    'Holds: Use weight-based hold targeting',
    'Use library weight based hold targeting',
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.max_org_unit_target_loops',
    'Holds: Maximum library target attempts',
    'When this value is set and greater than 0, the system will only attempt to find a copy at each possible branch the configured number of times',
    'integer'
);

COMMIT;

