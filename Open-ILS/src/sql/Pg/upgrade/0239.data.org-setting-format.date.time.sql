BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0239'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'format.date',
        oils_i18n_gettext(
            'format.date',
            'GUI: Format Dates with this pattern.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'format.date',
            'GUI: Format Dates with this pattern (examples: "yyyy-MM-dd" for "2010-04-26", "MMM d, yyyy" for "Apr 26, 2010")', 
            'coust', 
            'description'),
        'string'
), (
        'format.time',
        oils_i18n_gettext(
            'format.time',
            'GUI: Format Times with this pattern.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'format.time',
            'GUI: Format Times with this pattern (examples: "h:m:s.SSS a z" for "2:07:20.666 PM Eastern Daylight Time", "HH:mm" for "14:07")', 
            'coust', 
            'description'),
        'string'
);


COMMIT;
