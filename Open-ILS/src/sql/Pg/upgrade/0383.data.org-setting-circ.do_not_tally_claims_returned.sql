BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0383'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.do_not_tally_claims_returned',
        oils_i18n_gettext(
            'circ.do_not_tally_claims_returned',
            'Circulation: Do not include outstanding Claims Returned circulations in lump sum tallies in Patron Display.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'circ.do_not_tally_claims_returned',
            'In the Patron Display interface, the number of total active circulations for a given patron is presented in the Summary sidebar and underneath the Items Out navigation button.  This setting will prevent Claims Returned circulations from counting toward these tallies.',
            'coust', 
            'description'),
        'bool'
);

COMMIT;
