BEGIN;

SELECT evergreen.upgrade_deps_block_check('1407', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES 
(
    'acq.lineitem.sort_order.claims', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.sort_order.claims',
        'ACQ Claim-Ready Lineitem List Sort Order',
        'cwst', 'label')
),
(
    'acq.lineitem.page_size.claims', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.page_size.claims',
        'ACQ Claim-Ready Lineitem List Page Size',
        'cwst', 'label')
),
(
    'eg.acq.search.lineitems.filter_to_invoiceable', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.acq.search.lineitems.filter_to_invoiceable',
        'ACQ Lineitem Search Filter to Invoiceable',
        'cwst', 'label')
),
(
    'eg.acq.search.lineitems.keep_results', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.acq.search.lineitems.keep_results',
        'ACQ Lineitem Search Keep Results Between Searches',
        'cwst', 'label')
),
(
    'eg.acq.search.lineitems.trim_list', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.acq.search.lineitems.trim_list',
        'ACQ Lineitem Search Trim List When Keeping Results',
        'cwst', 'label')
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 650, 'ACQ_ALLOW_OVERSPEND', oils_i18n_gettext(650,
    'Allow a user to ignore a fund''s stop percentage.', 'ppl', 'description'))
;

COMMIT;


