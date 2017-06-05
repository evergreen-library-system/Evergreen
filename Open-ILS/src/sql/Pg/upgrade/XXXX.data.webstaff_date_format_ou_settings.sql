BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.org_unit_setting_type (
     name
    ,grp
    ,label
    ,description
    ,datatype
) VALUES ( ----------------------------------------
     'webstaff.format.dates'
    ,'gui'
    ,oils_i18n_gettext(
         'webstaff.format.dates'
        ,'Format Dates with this pattern'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.format.dates'
        ,'Format Dates with this pattern (examples: "yyyy-MM-dd" for "2010-04-26", "MMM d, yyyy" for "Apr 26, 2010").  This will be used in areas where a date without a timestamp is sufficient, like Date of Birth.'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.format.date_and_time'
    ,'gui'
    ,oils_i18n_gettext(
         'webstaff.format.date_and_time'
        ,'Format Date+Time with this pattern'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.format.date_and_time'
        ,'Format Date+Time with this pattern (examples: "yy-MM-dd h:m:s.SSS a" for "16-04-05 2:07:20.666 PM", "yyyy-dd-MMM HH:mm" for "2016-05-Apr 14:07").  This will be used in areas of the client where a date with a timestamp is needed, like Checkout, Due Date, or Record Created.'
        ,'coust'
        ,'description'
    )
    ,'string'
);

UPDATE
    config.org_unit_setting_type
SET
    label = 'Deprecated: ' || label -- FIXME: Is this okay?
WHERE
    name IN ('format.date','format.time')
;

-- for testing, setting removal:
--DELETE FROM actor.org_unit_setting WHERE name IN (
--     'webstaff.format.dates'
--    ,'webstaff.format.date_and_time'
--);
--DELETE FROM config.org_unit_setting_type_log WHERE field_name IN (
--     'webstaff.format.dates'
--    ,'webstaff.format.date_and_time'
--);
--DELETE FROM config.org_unit_setting_type WHERE name IN (
--     'webstaff.format.dates'
--    ,'webstaff.format.date_and_time'
--);
--UPDATE config.org_unit_setting_type SET label = REPLACE(label,'Deprecated: ','') WHERE name in ('format.date','format.time');

COMMIT;
