BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0426'); -- senator

INSERT INTO permission.perm_list VALUES
    (402, 'ADMIN_ACQ_DISTRIB_FORMULA', oils_i18n_gettext(402, 'Create/update/delete distribution formulae', 'ppl', 'description'))
    ,(403, 'ADMIN_ACQ_CLAIM', oils_i18n_gettext(403, 'Create/update/delete acquisitions claims', 'ppl', 'description'))
    ,(404, 'ADMIN_ACQ_CLAIM_EVENT_TYPE', oils_i18n_gettext(404, 'Create/update/delete acquisitions claim event types', 'ppl', 'description'))
    ,(405, 'ADMIN_ACQ_CLAIM_TYPE', oils_i18n_gettext(405, 'Create/update/delete acquisitions claim types', 'ppl', 'description'))
    ,(406, 'ADMIN_ACQ_FISCAL_YEAR', oils_i18n_gettext(406, 'Create/update/delete acquisitions fiscal years', 'ppl', 'description'))
    ,(407, 'ADMIN_ACQ_FUND_ALLOCATION_PERCENT', oils_i18n_gettext(407, 'Create/update/delete acquisitions fund allocation percentages', 'ppl', 'description'))
    ,(408, 'ADMIN_ACQ_FUND_TAG', oils_i18n_gettext(408, 'Create/update/delete acquisitions fund tags', 'ppl', 'description'))
    ,(409, 'ADMIN_ACQ_LINEITEM_ALERT_TEXT', oils_i18n_gettext(409, 'Create/update/delete acquisitions lineitem alert text', 'ppl', 'description'))
;

COMMIT;
