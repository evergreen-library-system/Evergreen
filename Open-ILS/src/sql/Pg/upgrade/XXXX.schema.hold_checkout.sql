BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
	('circ.clear_hold_on_checkout',
	 'circ',
 	oils_i18n_gettext('circ.clear_hold_on_checkout',
     		'Clear hold when other patron checks out item',
     		'coust', 'label'),
        oils_i18n_gettext('circ.clear_hold_on_checkout',
                 'When patron A checks out item on hold for patron B, ' ||
		 'automatically clear the hold for patron B. This is ' ||
                 'desirable when checking out item for family members',
     		'coust', 'description'),
   	'bool');

INSERT INTO actor.org_unit_setting (
    org_unit, name, value
) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.clear_hold_on_checkout',
    'false'
);

COMMIT;

