BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0081');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class ) 
    VALUES ( 
        'circ.holds.clear_shelf.copy_status',
        oils_i18n_gettext('circ.holds.clear_shelf.copy_status', 'Holds: Clear shelf copy status', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.clear_shelf.copy_status', 'Any copies that have not been put into reshelving, in-transit, or on-holds-shelf (for a new hold) during the clear shelf process will be put into this status.  This is basically a purgatory status for copies waiting to be pulled from the shelf and processed by hand', 'coust', 'description'),
        'link',
        'ccs'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.holds.clear_shelf.no_capture_holds',
        oils_i18n_gettext('circ.holds.clear_shelf.no_capture_holds', 'Holds: Bypass hold capture during clear shelf process', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.clear_shelf.no_capture_holds', 'During the clear shelf process, avoid capturing new holds on cleared items.', 'coust', 'description'),
        'bool'
    );


COMMIT;
