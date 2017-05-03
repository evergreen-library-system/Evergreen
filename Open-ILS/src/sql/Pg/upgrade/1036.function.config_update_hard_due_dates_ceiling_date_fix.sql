BEGIN;

SELECT evergreen.upgrade_deps_block_check('1036', :eg_version);

CREATE OR REPLACE FUNCTION config.update_hard_due_dates () RETURNS INT AS $func$
DECLARE
    temp_value  config.hard_due_date_values%ROWTYPE;
    updated     INT := 0;
BEGIN
    FOR temp_value IN
      SELECT  DISTINCT ON (hard_due_date) *
        FROM  config.hard_due_date_values
        WHERE active_date <= NOW() -- We've passed (or are at) the rollover time
        ORDER BY hard_due_date, active_date DESC -- Latest (nearest to us) active time
   LOOP
        UPDATE  config.hard_due_date
          SET   ceiling_date = temp_value.ceiling_date
          WHERE id = temp_value.hard_due_date
                AND ceiling_date <> temp_value.ceiling_date -- Time is equal if we've already updated the chdd
                AND temp_value.ceiling_date >= NOW(); -- Don't update ceiling dates to the past

        IF FOUND THEN
            updated := updated + 1;
        END IF;
    END LOOP;

    RETURN updated;
END;
$func$ LANGUAGE plpgsql;

COMMIT;
