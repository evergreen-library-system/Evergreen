
ALTER TABLE config.metabib_class ADD COLUMN combined BOOL NOT NULL DEFAULT FALSE;
UPDATE config.metabib_class SET combined = TRUE WHERE name = 'subject';

