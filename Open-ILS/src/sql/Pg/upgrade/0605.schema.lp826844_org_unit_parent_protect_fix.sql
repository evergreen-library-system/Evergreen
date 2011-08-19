-- Evergreen DB patch XXXX.schema.lp826844_org_unit_parent_protect_fix.sql
--
-- Correct the fact that actor.org_unit_parent_protect() may not work
-- due to 'IF' conditions in PL/pgSQL not necessarily processing in the
-- order written
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0605', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_parent_protect () RETURNS TRIGGER AS $$
	DECLARE
		current_aou actor.org_unit%ROWTYPE;
		seen_ous    INT[];
		depth_count INT;
	BEGIN
		current_aou := NEW;
		depth_count := 0;
		seen_ous := ARRAY[NEW.id];

		IF (TG_OP = 'UPDATE') THEN
			IF (NEW.parent_ou IS NOT DISTINCT FROM OLD.parent_ou) THEN
				RETURN NEW; -- Doing an UPDATE with no change, just return it
			END IF;
		END IF;

		LOOP
			IF current_aou.parent_ou IS NULL THEN -- Top of the org tree?
				RETURN NEW; -- No loop. Carry on.
			END IF;
			IF current_aou.parent_ou = ANY(seen_ous) THEN -- Parent is one we have seen?
				RAISE 'OU LOOP: Saw % twice', current_aou.parent_ou; -- LOOP! ABORT!
			END IF;
			-- Get the next one!
			SELECT INTO current_aou * FROM actor.org_unit WHERE id = current_aou.parent_ou;
			seen_ous := seen_ous || current_aou.id;
			depth_count := depth_count + 1;
			IF depth_count = 100 THEN
				RAISE 'OU CHECK TOO DEEP';
			END IF;
		END LOOP;

		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;


COMMIT;
