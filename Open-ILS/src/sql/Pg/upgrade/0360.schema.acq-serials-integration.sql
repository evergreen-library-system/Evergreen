BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0360'); -- miker

INSERT INTO acq.invoice_item_type (code,name) VALUES ('SUB',oils_i18n_gettext('SUB', 'Searial Subscription', 'aiit', 'name'));

ALTER TABLE acq.po_item ADD COLUMN target BIGINT;
ALTER TABLE acq.invoice_item ADD COLUMN target BIGINT;
ALTER TABLE asset.copy ADD COLUMN cost NUMERIC(8,2);

CREATE TABLE acq.serial_claim (
    id     SERIAL           PRIMARY KEY,
    type   INT              NOT NULL REFERENCES acq.claim_type
                                     DEFERRABLE INITIALLY DEFERRED,
    item    BIGINT          NOT NULL REFERENCES serial.item
                                     DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX serial_claim_lid_idx ON acq.serial_claim( item );

CREATE TABLE acq.serial_claim_event (
    id             BIGSERIAL        PRIMARY KEY,
    type           INT              NOT NULL REFERENCES acq.claim_event_type
                                             DEFERRABLE INITIALLY DEFERRED,
    claim          SERIAL           NOT NULL REFERENCES acq.serial_claim
                                             DEFERRABLE INITIALLY DEFERRED,
    event_date     TIMESTAMPTZ      NOT NULL DEFAULT now(),
    creator        INT              NOT NULL REFERENCES actor.usr
                                             DEFERRABLE INITIALLY DEFERRED,
    note           TEXT
);

CREATE INDEX serial_claim_event_claim_date_idx ON acq.serial_claim_event( claim, event_date );

COMMIT;

