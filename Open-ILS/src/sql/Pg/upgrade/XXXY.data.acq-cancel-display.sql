
BEGIN;

-- Update ACQ cancel reason names, but only those that 
-- have not already been locally modified from stock values.

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Invalid ISBN', 'acqcr', 'label')
    WHERE id = 1 AND label = 'invalid_isbn';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Postpone', 'acqcr', 'label')
    WHERE id = 2 AND label = 'postpone';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Delivered but Lost', 'acqcr', 'label')
    WHERE id = 3 AND label = 'delivered_but_lost';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Deleted', 'acqcr', 'label')
    WHERE id = 1002 AND label = 'Deleted';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Changed', 'acqcr', 'label')
    WHERE id = 1003 AND label = 'Changed';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: No Action', 'acqcr', 'label')
    WHERE id = 1004 AND label = 'No action';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Accepted without amendment', 'acqcr', 'label')
    WHERE id = 1005 AND label = 'Accepted without amendment';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Not Accepted', 'acqcr', 'label')
    WHERE id = 1007 AND label = 'Not accepted';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Not Found', 'acqcr', 'label')
    WHERE id = 1010 AND label = 'Not found';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed : Accepted with amendment', 'acqcr', 'label')
    WHERE id = 1024 AND label = 'Accepted with amendment, no confirmation required';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed : Split Quantity', 'acqcr', 'label')
    WHERE id = 1211 AND label = 'Split quantity';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed : Ordered Quantity', 'acqcr', 'label')
    WHERE id = 1221 AND label = 'Ordered quantity';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed : Pieces Delivered', 'acqcr', 'label')
    WHERE id = 1246 AND label = 'Pieces delivered';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed : Backorder', 'acqcr', 'label')
    WHERE id = 1283 AND label = 'Backorder quantity';

COMMIT;
