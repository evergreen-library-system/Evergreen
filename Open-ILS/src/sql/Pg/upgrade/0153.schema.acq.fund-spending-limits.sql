BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0153'); -- Scott McKellar

ALTER TABLE acq.fund
    ADD COLUMN balance_warning_percent INT
    CONSTRAINT balance_warning_percent_limit
        CHECK( balance_warning_percent <= 100 );

ALTER TABLE acq.fund
    ADD COLUMN balance_stop_percent INT
    CONSTRAINT balance_stop_percent_limit
        CHECK( balance_stop_percent <= 100 );

COMMIT;
