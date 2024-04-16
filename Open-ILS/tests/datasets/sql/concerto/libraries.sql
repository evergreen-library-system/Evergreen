INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (2, 1, 2, 'SYS1', oils_i18n_gettext(2, 'Example System 1', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (3, 1, 2, 'SYS2', oils_i18n_gettext(3, 'Example System 2', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (4, 2, 3, 'BR1', oils_i18n_gettext(4, 'Example Branch 1', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (5, 2, 3, 'BR2', oils_i18n_gettext(5, 'Example Branch 2', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (6, 3, 3, 'BR3', oils_i18n_gettext(6, 'Example Branch 3', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (7, 3, 3, 'BR4', oils_i18n_gettext(7, 'Example Branch 4', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (8, 4, 4, 'SL1', oils_i18n_gettext(8, 'Example Sub-library 1', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES 
    (9, 6, 5, 'BM1', oils_i18n_gettext(9, 'Example Bookmobile 1', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name) VALUES
    (10, 1, 2, 'SYS3', oils_i18n_gettext(10, 'Example System 3', 'aou', 'name'));
INSERT INTO actor.org_unit (id, parent_ou, ou_type, shortname, name, staff_catalog_visible) VALUES
    (11, 10, 3, 'BR5', oils_i18n_gettext(10, 'Example Branch 5', 'aou', 'name'), FALSE);

INSERT INTO actor.org_lasso (id, name, global) VALUES (1000001, 'Even Branches', FALSE);
INSERT INTO actor.org_lasso_map (lasso, org_unit) VALUES (1000001, 5), (1000001, 7);

INSERT INTO actor.org_lasso (id, name, global) VALUES (1000002, 'Non-branches', TRUE);
INSERT INTO actor.org_lasso_map (lasso, org_unit) VALUES (1000002, 8), (1000002, 9);

-- Address for the Consortium
SELECT evergreen.create_aou_address(1, '123 Main St.', NULL, 'Anywhere', 'GA', 'US', '30303', NULL);

-- Addresses for System 1
SELECT evergreen.create_aou_address(2, '234 Side St.', NULL, 'Anywhere', 'GA', 'US', '30304', NULL);

-- Addresses for System 2
SELECT evergreen.create_aou_address(3, '345 Corner Crescent', NULL, 'Elsewhere', 'GA', 'US', '30335', NULL);

-- Addresses for Branch 1
SELECT evergreen.create_aou_address(4, 'BR1', '123 Main St.', 'Anywhere', 'GA', 'US', '30303', 'billing mailing');
SELECT evergreen.create_aou_address(4, 'Holds and ILL', '125 Main St.', 'Anywhere', 'GA', 'US', '30303', 'interlibrary holds');

-- Addresses for Branch 2
SELECT evergreen.create_aou_address(5, 'BR2', '234 Side St.', 'Anywhere', 'GA', 'US', '30304', 'mailing');
SELECT evergreen.create_aou_address(5, 'BR2 - Billing', '234 Side St.', 'Anywhere', 'GA', 'US', '30304', 'billing');
SELECT evergreen.create_aou_address(5, 'BR2 - Holds and ILL', '234 Side St.', 'Anywhere', 'GA', 'US', '30304', 'interlibrary holds');

-- Addresses for Branch 3
SELECT evergreen.create_aou_address(6, 'BR3', '347 Corner Crescent', 'Elsewhere', 'GA', 'US', '30335', NULL);

-- Addresses for Branch 4
SELECT evergreen.create_aou_address(7, 'BR4', '446 Nowhere Road', 'Elsewhere', 'GA', 'US', '30404', 'mailing');
SELECT evergreen.create_aou_address(7, 'BR4 - Billing Dept', '446 Nowhere Road', 'Elsewhere', 'GA', 'US', '30404', 'billing');
SELECT evergreen.create_aou_address(7, 'BR4 - Holds and ILL', '756 Industrial Lane', 'Elsewhere', 'GA', 'US', '30304', 'interlibrary holds');

-- Hours for branches
INSERT INTO actor.hours_of_operation (id, dow_0_open, dow_0_close, dow_1_open, dow_1_close,
    dow_2_open, dow_2_close, dow_3_open, dow_3_close, dow_4_open, dow_4_close,
    dow_5_open, dow_5_close, dow_6_open, dow_6_close) VALUES
-- BR1 - closed on weekends (convention is 00:00 - 00:00)
    (4, '08:00', '23:30', '08:00', '23:30', '08:00', '23:30', '08:00', '23:30', '09:00', '23:30', '00:00', '00:00', '00:00', '00:00'),
-- BR2 - accept defaults of 09:00 - 17:00 for some days
    (5, '08:30', '21:30', '09:30', '14:30', '10:00', '21:30', '08:30', '17:00', '09:00', '17:00', '09:00', '17:00', '09:00', '17:00'),
-- BR3 - accept defaults of 09:00 - 17:00 for some days
    (6, '08:00', '23:30', '08:00', '23:30', '08:00', '23:30', '08:00', '23:30', '09:00', '23:30', '13:00', '23:30', '09:00', '23:30'),
-- BR4 - accept defaults of 09:00 - 17:00 for each day
    (7, '09:00', '17:00', '09:00', '17:00', '09:00', '17:00', '09:00', '17:00', '09:00', '17:00', '09:00', '17:00', '09:00', '17:00');

-- Set some information URLs for library branches
INSERT INTO actor.org_unit_setting(org_unit, name, value) VALUES
    (4, 'lib.info_url', '"http://example.com/BR1"'), -- BR1
    (5, 'lib.info_url', '"http://example.com/BR2"'), -- BR2
    (6, 'lib.info_url', '"http://br3.example.com"'), -- BR3
    (7, 'lib.info_url', '"http://br4.example.com/info"'); -- BR4


UPDATE actor.org_unit SET email = 'br1@example.com', phone = '(555) 555-0271' WHERE shortname = 'BR1';
UPDATE actor.org_unit SET email = 'br2@example.com', phone = '(555) 555-0272' WHERE shortname = 'BR2';
UPDATE actor.org_unit SET email = 'br3@example.com', phone = '(555) 555-0273' WHERE shortname = 'BR3';
UPDATE actor.org_unit SET email = 'br4@example.com', phone = '(555) 555-0274' WHERE shortname = 'BR4';
