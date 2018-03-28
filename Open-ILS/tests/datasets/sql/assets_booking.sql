-- Create call numbers
SELECT evergreen.populate_call_number(6, 'EQUIPMENT-1', 'IMPORT BOOKING', 1);
SELECT evergreen.populate_call_number(6, 'EQUIPMENT-2', 'IMPORT BOOKING', 1);
SELECT evergreen.populate_call_number(6, 'EQUIPMENT-3', 'IMPORT BOOKING', 1);
SELECT evergreen.populate_call_number(6, 'EQUIPMENT-4', 'IMPORT BOOKING', 1);
SELECT evergreen.populate_call_number(6, 'EQUIPMENT-5', 'IMPORT BOOKING', 1);
SELECT evergreen.populate_call_number(9, 'TECH', 'IMPORT BOOKING', 1);


-- Create copies
SELECT evergreen.populate_copy(6, 6, 'EQUIP', 'EQUIPMENT');
SELECT evergreen.populate_copy(9, 9, 'TECH', 'TECH');

