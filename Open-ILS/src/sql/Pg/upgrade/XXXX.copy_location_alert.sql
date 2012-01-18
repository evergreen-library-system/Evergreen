ALTER TABLE asset.copy_location
    ADD COLUMN checkin_alert BOOL NOT NULL DEFAULT FALSE;
