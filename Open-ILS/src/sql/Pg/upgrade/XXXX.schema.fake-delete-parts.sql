BEGIN;

ALTER TABLE biblio.monograph_part ADD COLUMN deleted BOOL NOT NULL DEFAULT FALSE;
CREATE RULE protect_mono_part_delete AS ON DELETE TO biblio.monograph_part DO INSTEAD (UPDATE biblio.monograph_part SET deleted = TRUE WHERE OLD.id = biblio.monograph_part.id);

COMMIT;

