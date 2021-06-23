BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.org_unit_setting_type
  SET description = $$How long to wait before allowing opportunistic capture of holds with a pickup library other than the context item's circulating library$$ -- ' vim
  WHERE name = 'circ.hold_stalling.soft';

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.pickup_hold_stalling.soft',
  'holds',
  'Pickup Library Soft stalling interval',
  'When set for the pickup library, this specifies that only items scanned at the pickup library can be opportunistically captured for this time period.  Example "5 days".  This setting takes precedence over "Soft stalling interval" (circ.hold_stalling.soft).',
  'interval',
  null
);

COMMIT;

