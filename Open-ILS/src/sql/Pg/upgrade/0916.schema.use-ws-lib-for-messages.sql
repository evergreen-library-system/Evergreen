BEGIN;

SELECT evergreen.upgrade_deps_block_check('0916', :eg_version);

CREATE OR REPLACE FUNCTION actor.convert_usr_note_to_message () RETURNS TRIGGER AS $$
DECLARE
	sending_ou INTEGER;
BEGIN
	IF NEW.pub THEN
		IF TG_OP = 'UPDATE' THEN
			IF OLD.pub = TRUE THEN
				RETURN NEW;
			END IF;
		END IF;

		SELECT INTO sending_ou aw.owning_lib
		FROM auditor.get_audit_info() agai
		JOIN actor.workstation aw ON (aw.id = agai.eg_ws);
		IF sending_ou IS NULL THEN
			SELECT INTO sending_ou home_ou
			FROM actor.usr
			WHERE id = NEW.creator;
		END IF;
		INSERT INTO actor.usr_message (usr, title, message, sending_lib)
			VALUES (NEW.usr, NEW.title, NEW.value, sending_ou);
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;
