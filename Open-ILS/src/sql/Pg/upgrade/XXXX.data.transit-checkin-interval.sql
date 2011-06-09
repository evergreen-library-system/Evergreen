-- Evergreen DB patch XXXX.data.transit-checkin-interval.sql
--
-- New org unit setting "circ.transit.min_checkin_interval"
-- New TRANSIT_CHECKIN_INTERVAL_BLOCK.override permission
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'circ.transit.min_checkin_interval',
    oils_i18n_gettext( 
        'circ.transit.min_checkin_interval', 
        'Circ:  Minimum Transit Checkin Interval',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'circ.transit.min_checkin_interval', 
        'In-Transit items checked in this close to the transit start time will be prevented from checking in',
        'coust',
        'label'
    ),
    'interval'
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (  
    509, 
    'TRANSIT_CHECKIN_INTERVAL_BLOCK.override', 
    oils_i18n_gettext(
        509,
        'Allows a user to override the TRANSIT_CHECKIN_INTERVAL_BLOCK event', 
        'ppl', 
        'description'
    )
);

-- add the perm to the default circ admin group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulation Administrator' AND
		aout.name = 'System' AND
		perm.code IN ( 'TRANSIT_CHECKIN_INTERVAL_BLOCK.override' );

COMMIT;
