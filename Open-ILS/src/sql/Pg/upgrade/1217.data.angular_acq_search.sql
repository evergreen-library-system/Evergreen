BEGIN;

SELECT evergreen.upgrade_deps_block_check('1217', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.acq.search.default.lineitems', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.lineitems',
    'Acquisitions Default Search: Lineitems',
    'cwst', 'label')
), (
    'eg.acq.search.default.purchaseorders', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.purchaseorders',
    'Acquisitions Default Search: Purchase Orders',
    'cwst', 'label')
), (
    'eg.acq.search.default.invoices', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.invoices',
    'Acquisitions Default Search: Invoices',
    'cwst', 'label')
), (
    'eg.acq.search.default.selectionlists', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.selectionlists',
    'Acquisitions Default Search: Selection Lists',
    'cwst', 'label')
);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.acq.search.lineitems.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.lineitems.run_immediately',
    'Acquisitions Search: Immediately Search Lineitems',
    'cwst', 'label')
), (
    'eg.acq.search.purchaseorders.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.purchaseorders.run_immediately',
    'Acquisitions Search: Immediately Search Purchase Orders',
    'cwst', 'label')
), (
    'eg.acq.search.invoices.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.invoices.run_immediately',
    'Acquisitions Search: Immediately Search Invoices',
    'cwst', 'label')
), (
    'eg.acq.search.selectionlists.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.selectionlists.run_immediately',
    'Acquisitions Search: Immediately Search Selection Lists',
    'cwst', 'label')
);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.search.lineitems', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.lineitems',
    'Grid Config: acq.search.lineitems',
    'cwst', 'label')
), (
    'eg.grid.acq.search.purchaseorders', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.purchaseorders',
    'Grid Config: acq.search.purchaseorders',
    'cwst', 'label')
), (
    'eg.grid.acq.search.selectionlists', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.selectionlists',
    'Grid Config: acq.search.selectionlists',
    'cwst', 'label')
), (
    'eg.grid.acq.search.invoices', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.invoices',
    'Grid Config: acq.search.invoices',
    'cwst', 'label')
);

COMMIT;
