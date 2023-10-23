BEGIN;

ALTER TABLE biblio.monograph_part
    ADD COLUMN creator INTEGER DEFAULT 1,
    ADD COLUMN editor INTEGER DEFAULT 1,
    ADD COLUMN create_date TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN edit_date TIMESTAMPTZ DEFAULT now();

UPDATE biblio.monograph_part SET creator=1, editor=1, create_date=now(),edit_date=now();

ALTER TABLE biblio.monograph_part
    ALTER COLUMN creator SET NOT NULL,
    ALTER COLUMN editor SET NOT NULL,
    ALTER COLUMN create_date SET NOT NULL,
    ALTER COLUMN edit_date SET NOT NULL;

COMMIT;