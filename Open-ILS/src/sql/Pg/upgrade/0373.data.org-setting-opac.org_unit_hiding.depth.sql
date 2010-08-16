BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0373'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'opac.org_unit_hiding.depth',
        oils_i18n_gettext(
            'opac.org_unit_hiding.depth',
            'OPAC: Org Unit Hiding Depth', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'opac.org_unit_hiding.depth',
            'This will hide certain org units in the public OPAC if the Original Location (url param "ol") for the OPAC inherits this setting.  This setting specifies an org unit depth, that together with the OPAC Original Location determines which section of the Org Hierarchy should be visible in the OPAC.  For example, a stock Evergreen installation will have a 3-tier hierarchy (Consortium/System/Branch), where System has a depth of 1 and Branch has a depth of 2.  If this setting contains a depth of 1 in such an installation, then every library in the System in which the Original Location belongs will be visible, and everything else will be hidden.  A depth of 0 will effectively make every org visible.  The embedded OPAC in the staff client ignores this setting.', 
            'coust', 
            'description'),
        'integer'
);

COMMIT;
