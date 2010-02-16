BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0162'); -- miker

CREATE TABLE acq.invoice_method (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL -- i18n-ize
);
INSERT INTO acq.invoice_method (code,name) VALUES ('EDI',oils_i18n_gettext('EDI', 'EDI', 'acqim', 'name'));
INSERT INTO acq.invoice_method (code,name) VALUES ('PPR',oils_i18n_gettext('PPR', 'Paper', 'acqit', 'name'));


CREATE TABLE acq.invoice (
    id          SERIAL      PRIMARY KEY,
    receiver    INT         NOT NULL REFERENCES actor.org_unit (id),
    provider    INT         NOT NULL REFERENCES acq.provider (id),
    shipper     INT         NOT NULL REFERENCES acq.provider (id),
    recv_date   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recv_method TEXT        NOT NULL REFERENCES acq.invoice_method (code) DEFAULT 'EDI',
    inv_type    TEXT,       -- A "type" field is desired, but no idea what goes here
    inv_ident   TEXT        NOT NULL -- vendor-supplied invoice id/number
);

CREATE TABLE acq.invoice_entry (
    id              SERIAL      PRIMARY KEY,
    invoice         INT         NOT NULL REFERENCES acq.invoice (id) ON DELETE CASCADE,
    purchase_order  INT         REFERENCES acq.purchase_order (id) ON UPDATE CASCADE ON DELETE SET NULL,
    lineitem        INT         REFERENCES acq.lineitem (id) ON UPDATE CASCADE ON DELETE SET NULL,
    inv_item_count  INT         NOT NULL, -- How many acqlids did they say they sent
    phys_item_count INT, -- and how many did staff count
    note            TEXT,
    billed_per_item BOOL,
    cost_billed     NUMERIC(8,2),
    actual_cost     NUMERIC(8,2)
);

CREATE TABLE acq.invoice_item_type (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL -- i18n-ize
);
INSERT INTO acq.invoice_item_type (code,name) VALUES ('TAX',oils_i18n_gettext('TAX', 'Tax', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('PRO',oils_i18n_gettext('PRO', 'Processing Fee', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('SHP',oils_i18n_gettext('SHP', 'Shipping Charge', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('HND',oils_i18n_gettext('HND', 'Handling Charge', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('ITM',oils_i18n_gettext('ITM', 'Non-library Item', 'aiit', 'name'));

CREATE TABLE acq.invoice_item ( -- for invoice-only debits: taxes/fees/non-bib items/etc
    id              SERIAL      PRIMARY KEY,
    invoice         INT         NOT NULL REFERENCES acq.invoice (id) ON UPDATE CASCADE ON DELETE CASCADE,
    purchase_order  INT         REFERENCES acq.purchase_order (id) ON UPDATE CASCADE ON DELETE SET NULL,
    fund_debit      INT         REFERENCES acq.fund_debit (id),
    inv_item_type   TEXT        NOT NULL REFERENCES acq.invoice_item_type (code),
    title           TEXT,
    author          TEXT,
    note            TEXT,
    cost_billed     NUMERIC(8,2),
    actual_cost     NUMERIC(8,2)
);

COMMIT;

