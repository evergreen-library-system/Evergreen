BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0442'); -- tsbere via miker

DROP TABLE config.hard_due_date;

CREATE TABLE config.hard_due_date (
		id			SERIAL		PRIMARY KEY,
		name		TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
		ceiling_date	TIMESTAMPTZ	NOT NULL,
		forceto		BOOL		NOT NULL,
		owner		INT			NOT NULL
);

CREATE TABLE config.hard_due_date_values (
    id                  SERIAL      PRIMARY KEY,
    hard_due_date       INT         NOT NULL REFERENCES config.hard_due_date (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    ceiling_date        TIMESTAMPTZ NOT NULL,
    active_date         TIMESTAMPTZ NOT NULL
);

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN hard_due_date INT REFERENCES config.hard_due_date (id);

ALTER TABLE config.rule_circ_duration DROP COLUMN date_ceiling;

CREATE OR REPLACE FUNCTION config.update_hard_due_dates () RETURNS INT AS $func$
DECLARE
    temp_value  config.hard_due_date_values%ROWTYPE;
    updated     INT := 0;
BEGIN
    FOR temp_value IN
      SELECT  DISTINCT ON (hard_due_date) *
        FROM  config.hard_due_date_values
        WHERE active_date <= NOW() -- We've passed (or are at) the rollover time
        ORDER BY active_date DESC -- Latest (nearest to us) active time
   LOOP
        UPDATE  config.hard_due_date
          SET   ceiling_date = temp_value.ceiling_date
          WHERE id = temp_value.hard_due_date
                AND ceiling_date <> temp_value.ceiling_date; -- Time is equal if we've already updated the chdd

        IF FOUND THEN
            updated := updated + 1;
        END IF;
    END LOOP;

    RETURN updated;
END;
$func$ LANGUAGE plpgsql;

COMMIT;

