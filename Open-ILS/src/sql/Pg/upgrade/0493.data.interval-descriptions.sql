BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0493'); -- dbs

UPDATE config.org_unit_setting_type
    SET description = 'Amount of time before a hold expires at which point the patron should be alerted. Examples: "5 days", "1 hour"'
    WHERE label = 'Holds: Expire Alert Interval';

UPDATE config.org_unit_setting_type
    SET description = 'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the default estimated length of time to assume an item will be checked out. Examples: "3 weeks", "7 days"'
    WHERE label = 'Holds: Default Estimated Wait';

UPDATE config.org_unit_setting_type
    SET description = 'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the minimum estimated length of time to assume an item will be checked out. Examples: "1 week", "5 days"'
    WHERE label = 'Holds: Minimum Estimated Wait';

UPDATE config.org_unit_setting_type
    SET description = 'The purpose is to provide an interval of time after an item goes into the on-holds-shelf status before it appears to patrons that it is actually on the holds shelf.  This gives staff time to process the item before it shows as ready-for-pickup. Examples: "5 days", "1 hour"'
    WHERE label = 'Hold Shelf Status Delay';

COMMIT;
