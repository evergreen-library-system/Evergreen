-- Create call numbers
SELECT evergreen.populate_call_number(4, 'G880 ', 'IMPORT G880', NULL); -- BR1
SELECT evergreen.populate_call_number(5, 'G880 ', 'IMPORT G880', NULL); -- BR2
SELECT evergreen.populate_call_number(6, 'G880 ', 'IMPORT G880', NULL); -- BR3
SELECT evergreen.populate_call_number(7, 'G880 ', 'IMPORT G880', NULL); -- BR4
SELECT evergreen.populate_call_number(9, 'G880 ', 'IMPORT G880', NULL); -- BM1

-- Create copies
SELECT evergreen.populate_copy(4, 4, 'G88040000', 'G880'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'G88050000', 'G880'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'G88060000', 'G880'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'G88070000', 'G880'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'G88090000', 'G880'); -- BM1

SELECT evergreen.populate_copy(4, 4, 'G88041000', 'G880'); -- BR1
SELECT evergreen.populate_copy(5, 5, 'G88051000', 'G880'); -- BR2
SELECT evergreen.populate_copy(6, 6, 'G88061000', 'G880'); -- BR3
SELECT evergreen.populate_copy(7, 7, 'G88071000', 'G880'); -- BR4
SELECT evergreen.populate_copy(9, 9, 'G88091000', 'G880'); -- BM1
