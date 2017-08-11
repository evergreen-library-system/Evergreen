BEGIN;

SELECT evergreen.upgrade_deps_block_check('1054', :eg_version);

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

CREATE OR REPLACE FUNCTION action.push_circ_due_time () RETURNS TRIGGER AS $$
DECLARE
    proper_tz TEXT := COALESCE(
        oils_json_to_text((
            SELECT value
              FROM  actor.org_unit_ancestor_setting('lib.timezone',NEW.circ_lib)
              LIMIT 1
        )),
        CURRENT_SETTING('timezone')
    );
BEGIN

    IF (EXTRACT(EPOCH FROM NEW.duration)::INT % EXTRACT(EPOCH FROM '1 day'::INTERVAL)::INT) = 0 -- day-granular duration
        AND SUBSTRING((NEW.due_date AT TIME ZONE proper_tz)::TIME::TEXT FROM 1 FOR 8) <> '23:59:59' THEN -- has not yet been pushed
        NEW.due_date = ((NEW.due_date AT TIME ZONE proper_tz)::DATE + '1 day'::INTERVAL - '1 second'::INTERVAL) || ' ' || proper_tz;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

\qecho The following query will adjust all historical, unaged circulations so
\qecho that if their due date field is pushed to the end of the day, it is done
\qecho in the circulating library''''s time zone, and not the server time zone.
\qecho 
\qecho It is safe to run this after any change to library time zones.
\qecho 
\qecho Running this is not required, as no code before this change has
\qecho depended on the time string of '''23:59:59'''.  It is also not necessary
\qecho if all of your libraries are in the same time zone, and that time zone
\qecho is the same as the database''''s configured time zone.
\qecho 
\qecho 'DO $$'
\qecho 'declare'
\qecho '    new_tz  text;'
\qecho '    ou_id   int;'
\qecho 'begin'
\qecho '    for ou_id in select id from actor.org_unit loop'
\qecho '        for new_tz in select oils_json_to_text(value) from actor.org_unit_ancestor_setting('''lib.timezone''',ou_id) loop'
\qecho '            if new_tz is not null then'
\qecho '                update  action.circulation'
\qecho '                  set   due_date = (due_date::timestamp || ''' ''' || new_tz)::timestamptz'
\qecho '                  where circ_lib = ou_id'
\qecho '                        and substring((due_date at time zone new_tz)::time::text from 1 for 8) <> '''23:59:59''';'
\qecho '            end if;'
\qecho '        end loop;'
\qecho '    end loop;'
\qecho 'end;'
\qecho '$$;'
\qecho 
