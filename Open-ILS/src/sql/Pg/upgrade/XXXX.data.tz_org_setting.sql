BEGIN;

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype ) VALUES

( 'lib.timezone', 'lib',
    oils_i18n_gettext('lib.timezone',
        'Library time zone',
        'coust', 'label'),
    oils_i18n_gettext('lib.timezone',
        'Define the time zone in which a library physically resides',
        'coust', 'description'),
    'string');

ALTER TABLE actor.org_unit_closed ADD COLUMN full_day BOOLEAN DEFAULT FALSE;
ALTER TABLE actor.org_unit_closed ADD COLUMN multi_day BOOLEAN DEFAULT FALSE;

UPDATE actor.org_unit_closed SET multi_day = TRUE
  WHERE close_start::DATE <> close_end::DATE;

UPDATE actor.org_unit_closed SET full_day = TRUE
  WHERE close_start::DATE = close_end::DATE
        AND SUBSTRING(close_start::time::text FROM 1 FOR 8) = '00:00:00'
        AND SUBSTRING(close_end::time::text FROM 1 FOR 8) = '23:59:59';

COMMIT;

