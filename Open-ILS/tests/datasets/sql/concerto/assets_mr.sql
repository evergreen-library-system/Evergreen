-- Create call numbers
SELECT evergreen.populate_call_number(4, 'MR ', 'IMPORT MR', NULL); -- BR1
SELECT evergreen.populate_call_number(5, 'MR ', 'IMPORT MR', NULL); -- BR2
SELECT evergreen.populate_call_number(6, 'MR ', 'IMPORT MR', NULL); -- BR3
SELECT evergreen.populate_call_number(7, 'MR ', 'IMPORT MR', NULL); -- BR4
SELECT evergreen.populate_call_number(9, 'MR ', 'IMPORT MR', NULL); -- BM1

-- Create copies
SELECT evergreen.populate_copy(4, 4, 'MR40000', 'MR'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'MR50000', 'MR'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'MR60000', 'MR'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'MR70000', 'MR'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'MR90000', 'MR'); -- BM1

SELECT evergreen.populate_copy(4, 4, 'MR41000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR42000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR43000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR44000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR45000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR46000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR47000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR48000', 'MR'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'MR49000', 'MR'); -- BR1

SELECT evergreen.populate_copy(5, 5, 'MR51000', 'MR'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'MR61000', 'MR'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'MR71000', 'MR'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'MR91000', 'MR'); -- BM1
