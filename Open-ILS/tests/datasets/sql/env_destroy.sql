
-- clean up our temp tables / functions
DROP TABLE marcxml_import;
DROP FUNCTION evergreen.create_aou_address(INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION evergreen.populate_call_number(INTEGER, TEXT, TEXT);
DROP FUNCTION evergreen.populate_call_number(INTEGER, TEXT, TEXT, INTEGER);
DROP FUNCTION evergreen.generate_price();
DROP FUNCTION evergreen.populate_copy(INTEGER, INTEGER, TEXT, TEXT);
DROP FUNCTION evergreen.next_copy (BIGINT);
DROP FUNCTION evergreen.next_bib (BIGINT);
DROP FUNCTION evergreen.populate_circ 
    (INTEGER, INTEGER, BIGINT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN);
DROP FUNCTION evergreen.populate_hold 
    (TEXT, BIGINT, INTEGER, INTEGER, INTEGER, BOOLEAN, TIMESTAMP WITH TIME ZONE, TEXT);
DROP FUNCTION evergreen.populate_booking_resource_type(INTEGER, TEXT);
DROP FUNCTION evergreen.populate_booking_resource(TEXT);
