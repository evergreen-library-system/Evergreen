BEGIN;

SELECT evergreen.upgrade_deps_block_check('1226', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.provider.addresses', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.addresses',
    'Grid Config: acq.provider.addresses',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.attributes', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.attributes',
    'Grid Config: acq.provider.attributes',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.contact.addresses', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.contact.addresses',
    'Grid Config: acq.provider.contact.addresses',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.contacts', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.contacts',
    'Grid Config: acq.provider.contacts',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.edi_accounts', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.edi_accounts',
    'Grid Config: acq.provider.edi_accounts',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.edi_messages', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.edi_messages',
    'Grid Config: acq.provider.edi_messages',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.holdings', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.holdings',
    'Grid Config: acq.provider.holdings',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.invoices', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.invoices',
    'Grid Config: acq.provider.invoices',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.purchaseorders', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.purchaseorders',
    'Grid Config: acq.provider.purchaseorders',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.search.results', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.search.results',
    'Grid Config: acq.provider.search.results',
    'cwst', 'label')
);

COMMIT;
