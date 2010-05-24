BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0274'); -- Scott McKellar

UPDATE config.org_unit_setting_type SET
	name = 'circ.holds.default_estimated_wait_interval',
	label = 'Holds: Default Estimated Wait',
	description = 'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the default estimated length of time to assume an item will be checked out.',
	datatype = 'interval'
WHERE name = 'circ.hold_estimate_wait_interval';

UPDATE actor.org_unit_setting SET
	name = 'circ.holds.default_estimated_wait_interval',
	value = value || ' days'
WHERE name = 'circ.hold_estimate_wait_interval';

INSERT INTO config.org_unit_setting_type (
	name,
	label,
	description,
	datatype
) VALUES (
	'circ.holds.min_estimated_wait_interval',
	'Holds: Minimum Estimated Wait',
	'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the minimum estimated length of time to assume an item will be checked out.',
	'interval'
);

COMMIT;
