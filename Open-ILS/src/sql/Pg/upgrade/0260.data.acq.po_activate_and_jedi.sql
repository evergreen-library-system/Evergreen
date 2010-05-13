BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0260');

INSERT INTO action_trigger.validator (module, description) 
    VALUES (
        'Acq::PurchaseOrderEDIRequired',
        oils_i18n_gettext(
            'Acq::PurchaseOrderEDIRequired',
            'Purchase order is delivered via EDI',
            'atval',
            'description'
        )
    );

INSERT INTO action_trigger.reactor (module, description)
    VALUES (
        'GeneratePurchaseOrderJEDI',
        oils_i18n_gettext(
            'GeneratePurchaseOrderJEDI',
            'Creates purchase order JEDI (JSON EDI) for subsequent EDI processing',
            'atreact',
            'description'
        )
    );

UPDATE action_trigger.hook 
    SET 
        key = 'acqpo.activated', 
        passive = FALSE,
        description = oils_i18n_gettext(
            'acqpo.activated',
            'Purchase order was activated',
            'ath',
            'description'
        )
    WHERE key = 'format.po.jedi';

UPDATE action_trigger.event_definition 
    SET 
        hook = 'acqpo.activated', 
        validator = 'Acq::PurchaseOrderEDIRequired',
        reactor = 'GeneratePurchaseOrderJEDI'
    WHERE id = 23; 

COMMIT;

