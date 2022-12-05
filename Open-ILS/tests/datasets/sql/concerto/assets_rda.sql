-- Create call numbers
SELECT evergreen.populate_call_number(4, 'RDA ', 'IMPORT RDA', NULL); -- BR1
SELECT evergreen.populate_call_number(5, 'RDA ', 'IMPORT RDA', NULL); -- BR2
SELECT evergreen.populate_call_number(6, 'RDA ', 'IMPORT RDA', NULL); -- BR3
SELECT evergreen.populate_call_number(7, 'RDA ', 'IMPORT RDA', NULL); -- BR4
SELECT evergreen.populate_call_number(9, 'RDA ', 'IMPORT RDA', NULL); -- BM1

-- Create copies
SELECT evergreen.populate_copy(4, 4, 'RDA40000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'RDA50000', 'RDA'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'RDA60000', 'RDA'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'RDA70000', 'RDA'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'RDA90000', 'RDA'); -- BM1

SELECT evergreen.populate_copy(4, 4, 'RDA41000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA42000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA43000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA44000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA45000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA46000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA47000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA48000', 'RDA'); -- BR1
SELECT evergreen.populate_copy(4, 4, 'RDA49000', 'RDA'); -- BR1

SELECT evergreen.populate_copy(5, 5, 'RDA51000', 'RDA'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'RDA61000', 'RDA'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'RDA71000', 'RDA'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'RDA91000', 'RDA'); -- BM1
