BEGIN;

SELECT evergreen.upgrade_deps_block_check('1462', :eg_version);

INSERT INTO acq.edi_attr (key, label) VALUES
    ('LINEITEM_SEQUENTIAL_ID',
        oils_i18n_gettext('LINEITEM_SEQUENTIAL_ID',
        'Lineitems Are Enumerated Sequentially', 'aea', 'label'));

COMMIT;
