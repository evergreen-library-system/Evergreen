CREATE OR REPLACE FUNCTION actor.org_unit_parent_protect () RETURNS TRIGGER AS $$
    DECLARE
        current_aou actor.org_unit%ROWTYPE;
        seen_ous    INT[];
        depth_count INT;
	BEGIN
        current_aou := NEW;
        depth_count := 0;
        seen_ous := ARRAY[NEW.id];
        IF TG_OP = 'INSERT' OR NEW.parent_ou IS DISTINCT FROM OLD.parent_ou THEN
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
        END IF;
		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER actor_org_unit_parent_protect_trigger
    BEFORE INSERT OR UPDATE ON actor.org_unit FOR EACH ROW
    EXECUTE PROCEDURE actor.org_unit_parent_protect ();
