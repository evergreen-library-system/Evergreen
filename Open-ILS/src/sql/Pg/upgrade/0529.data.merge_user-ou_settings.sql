BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0529');

INSERT INTO config.org_unit_setting_type 
( name, label, description, datatype ) VALUES 
( 'circ.user_merge.delete_addresses', 
  'Circ:  Patron Merge Address Delete', 
  'Delete address(es) of subordinate user(s) in a patron merge', 
   'bool'
);

INSERT INTO config.org_unit_setting_type 
( name, label, description, datatype ) VALUES 
( 'circ.user_merge.delete_cards', 
  'Circ: Patron Merge Barcode Delete', 
  'Delete barcode(s) of subordinate user(s) in a patron merge', 
  'bool'
);

INSERT INTO config.org_unit_setting_type 
( name, label, description, datatype ) VALUES 
( 'circ.user_merge.deactivate_cards', 
  'Circ:  Patron Merge Deactivate Card', 
  'Mark barcode(s) of subordinate user(s) in a patron merge as inactive', 
  'bool'
);

COMMIT;
