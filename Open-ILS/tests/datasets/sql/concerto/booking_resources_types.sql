-- Create booking resource types
INSERT INTO booking.resource_type(id, name, owner, catalog_item, transferable)
VALUES (555, 'Meeting room', 1, False, True),
(556, 'Phone charger', 3, False, True);

-- Create booking resource types from MARC
SELECT evergreen.populate_booking_resource_type(6, 'IMPORT BOOKING');

-- Create booking resources
INSERT INTO booking.resource(owner, type, barcode)
VALUES (4, 555, 'ROOM1231'),
(4, 555, 'ROOM1232'),
(4, 555, 'ROOM1233' ),
(7, 555, 'ROOM2341'),
(7, 555, 'ROOM2342'),
(7, 555, 'ROOM2343'),
(7, 555, 'ROOM2344'),
(7, 555, 'ROOM2345'),
(7, 555, 'ROOM2346'),
(6, 556, 'IPHONE-CHARGER-01'),
(6, 556, 'IPHONE-CHARGER-02'),
(7, 556, 'ANDROID-CHARGER-01'),
(7, 556, 'IPHONE-CHARGER-03'),
(9, 556, 'IPHONE-CHARGER-04'),
(9, 556, 'IPHONE-CHARGER-05');

-- Create booking resources from item records
SELECT evergreen.populate_booking_resource('EQUIP');
