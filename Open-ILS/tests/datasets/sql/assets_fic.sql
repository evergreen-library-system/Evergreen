-- Create call numbers
SELECT evergreen.populate_call_number(4, 'FIC ', 'IMPORT FIC', NULL); -- BR1
SELECT evergreen.populate_call_number(5, 'FIC ', 'IMPORT FIC', NULL); -- BR2
SELECT evergreen.populate_call_number(6, 'FIC ', 'IMPORT FIC', NULL); -- BR3
SELECT evergreen.populate_call_number(7, 'FIC ', 'IMPORT FIC', NULL); -- BR4
SELECT evergreen.populate_call_number(9, 'FIC ', 'IMPORT FIC', NULL); -- BM1

-- Create copies
SELECT evergreen.populate_copy(4, 4, 'FIC40000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'FIC50000', 'FIC'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'FIC60000', 'FIC'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'FIC70000', 'FIC'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'FIC90000', 'FIC'); -- BM1

SELECT evergreen.populate_copy(4, 4, 'FIC41000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC42000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC43000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC44000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC45000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC46000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC47000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC48000', 'FIC'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'FIC49000', 'FIC'); -- BR1

SELECT evergreen.populate_copy(5, 5, 'FIC51000', 'FIC'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'FIC61000', 'FIC'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'FIC71000', 'FIC'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'FIC91000', 'FIC'); -- BM1
