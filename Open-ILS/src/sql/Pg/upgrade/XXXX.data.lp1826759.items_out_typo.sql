BEGIN;

UPDATE config.org_unit_setting_type
    SET description = oils_i18n_gettext('ui.circ.show_billing_tab_on_bills',
        'If enabled and a patron has outstanding bills and the alert page is not required, show the billing tab by default, instead of the checkout tab, when a patron is loaded',
        'coust', 'description')
    WHERE name = 'ui.circ.show_billing_tab_on_bills';
UPDATE config.org_unit_setting_type    
    SET description = oils_i18n_gettext('ui.circ.show_billing_tab_on_bills',
        'If enabled and a patron has outstanding bills and the alert page is not required, show the billing tab by default, instead of the checkout tab, when a patron is loaded',
        'coust', 'description')
    WHERE name = 'ui.circ.show_billing_tab_on_bills';
UPDATE config.org_unit_setting_type
    SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.longoverdue';
UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.lost';
UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.claimsreturned';

END;
