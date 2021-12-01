BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

CREATE TABLE acq.shipment_notification (
    id              SERIAL      PRIMARY KEY,
    receiver        INT         NOT NULL REFERENCES actor.org_unit (id),
    provider        INT         NOT NULL REFERENCES acq.provider (id),
    shipper         INT         NOT NULL REFERENCES acq.provider (id),
    recv_date       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recv_method     TEXT        NOT NULL REFERENCES acq.invoice_method (code) DEFAULT 'EDI',
    process_date    TIMESTAMPTZ,
    processed_by    INT         REFERENCES actor.usr(id) ON DELETE SET NULL,
    container_code  TEXT        NOT NULL, -- vendor-supplied super-barcode
    lading_number   TEXT,       -- informational
    note            TEXT,
    CONSTRAINT      container_code_once_per_provider UNIQUE(provider, container_code)
);

CREATE INDEX acq_asn_container_code_idx ON acq.shipment_notification (container_code);

CREATE TABLE acq.shipment_notification_entry (
    id                      SERIAL  PRIMARY KEY,
    shipment_notification   INT NOT NULL REFERENCES acq.shipment_notification (id)
                            ON DELETE CASCADE,
    lineitem                INT REFERENCES acq.lineitem (id)
                            ON UPDATE CASCADE ON DELETE SET NULL,
    item_count              INT NOT NULL -- How many items the provider shipped
);

/* TODO alter valid_message_type constraint */

ALTER TABLE acq.edi_message DROP CONSTRAINT valid_message_type;
ALTER TABLE acq.edi_message ADD CONSTRAINT valid_message_type
CHECK (
    message_type IN (
        'ORDERS',
        'ORDRSP',
        'INVOIC',
        'OSTENQ',
        'OSTRPT',
        'DESADV'
    )
);

COMMIT;

/* UNDO

DELETE FROM acq.edi_message WHERE message_type = 'DESADV';

DELETE FROM acq.shipment_notification_entry;
DELETE FROM acq.shipment_notification;

ALTER TABLE acq.edi_message DROP CONSTRAINT valid_message_type;
ALTER TABLE acq.edi_message ADD CONSTRAINT valid_message_type
CHECK (
    message_type IN (
        'ORDERS',
        'ORDRSP',
        'INVOIC',
        'OSTENQ',
        'OSTRPT'
    )
);

DROP TABLE acq.shipment_notification_entry;
DROP TABLE acq.shipment_notification;

*/
