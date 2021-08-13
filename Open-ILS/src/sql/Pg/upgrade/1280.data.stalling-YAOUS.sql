BEGIN;

SELECT evergreen.upgrade_deps_block_check('1280', :eg_version);

UPDATE config.org_unit_setting_type
  SET description = $$How long to wait before allowing opportunistic capture of holds with a pickup library other than the context item's circulating library$$ -- ' vim
  WHERE name = 'circ.hold_stalling.soft';

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.pickup_hold_stalling.soft',
  'holds',
  'Pickup Library Soft stalling interval',
  'When set for the pickup library, this specifies that for holds with a request time age smaller than this interval only items scanned at the pickup library can be opportunistically captured. Example "5 days". This setting takes precedence over "Soft stalling interval" (circ.hold_stalling.soft) when the interval is in force.',
  'interval',
  null
);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.pickup_hold_stalling.hard',
  'holds',
  'Pickup Library Hard stalling interval',
  'When set for the pickup library, this specifies that no items with a calculated proximity greater than 0 from the pickup library can be directly targeted for this time period if there are local available copies.  Example "3 days".',
  'interval',
  null
);

COMMIT;

