-- Create call numbers
SELECT evergreen.populate_call_number(4, 'FRE ', 'IMPORT FRE', NULL); -- BR1
SELECT evergreen.populate_call_number(5, 'FRE ', 'IMPORT FRE', NULL); -- BR2
SELECT evergreen.populate_call_number(6, 'FRE ', 'IMPORT FRE', NULL); -- BR3
SELECT evergreen.populate_call_number(7, 'FRE ', 'IMPORT FRE', NULL); -- BR4
SELECT evergreen.populate_call_number(9, 'FRE ', 'IMPORT FRE', NULL); -- BM1

-- Create copies
SELECT evergreen.populate_copy(4, 4, 'FRE40000', 'FRE'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'FRE50000', 'FRE'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'FRE60000', 'FRE'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'FRE70000', 'FRE'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'FRE90000', 'FRE'); -- BM1

SELECT evergreen.populate_copy(4, 4, 'FRE41000', 'FRE'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'FRE51000', 'FRE'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'FRE61000', 'FRE'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'FRE71000', 'FRE'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'FRE91000', 'FRE'); -- BM1

-- delete the last 10 FRE copies
DELETE FROM asset.copy WHERE id IN (
    SELECT id 
    FROM asset.copy 
    WHERE barcode LIKE 'FRE%'
    ORDER BY id DESC LIMIT 10);
