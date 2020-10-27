-- Create call numbers
SELECT evergreen.populate_call_number(4, 'CZE ', 'IMPORT CZE', NULL); -- BR1
SELECT evergreen.populate_call_number(7, 'CZE ', 'IMPORT CZE', NULL); -- BR4

-- Create copies
SELECT evergreen.populate_copy(4, 4, 'CZE40000', 'CZE'); -- BR1
SELECT evergreen.populate_copy(7, 7, 'CZE70000', 'CZE'); -- BR4

SELECT evergreen.populate_copy(7, 7, 'CZE71000', 'CZE'); -- BR4
