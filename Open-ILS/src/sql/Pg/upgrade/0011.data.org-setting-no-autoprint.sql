BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0011');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.staff_client.do_not_auto_attempt_print',
    'Disable Automatic Print Attempt Type List',
    'Disable automatic print attempts from staff client interfaces for the receipt types in this list.  Possible values: "Checkout", "Bill Pay", "Hold Slip", "Transit Slip", and "Hold/Transit Slip".  This is different from the Auto-Print checkbox in the pertinent interfaces in that it disables automatic print attempts altogether, rather than encouraging silent printing by suppressing the print dialog.  The Auto-Print checkbox in these interfaces have no effect on the behavior for this setting.  In the case of the Hold, Transit, and Hold/Transit slips, this also suppresses the alert dialogs that precede the print dialog (the ones that offer Print and Do Not Print as options).',
    'array' 
);

COMMIT;
