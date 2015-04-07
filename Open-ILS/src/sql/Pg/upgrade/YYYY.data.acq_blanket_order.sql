BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO acq.invoice_item_type (code, blanket, name) VALUES (
    'BLA', TRUE, oils_i18n_gettext('BLA', 'Blanket Order', 'aiit', 'name'));

COMMIT;
