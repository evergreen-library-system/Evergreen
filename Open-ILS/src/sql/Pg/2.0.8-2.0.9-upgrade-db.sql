BEGIN;


-- Fix LP#825303 by allowing for ancestor OUs to be checked
-- when retrieving the default classification scheme.
--
INSERT INTO config.upgrade_log (version) VALUES ('0600');

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    IF NEW.label_class IS NULL THEN
            NEW.label_class := COALESCE(
            (
                SELECT substring(value from E'\\d+')::integer
                FROM actor.org_unit_ancestor_setting('cat.default_classification_scheme', NEW.owning_lib)
            ), 1
        );
    END IF;

    EXECUTE 'SELECT ' || acnc.normalizer || '(' || 
       quote_literal( NEW.label ) || ')'
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;
    NEW.label_sortkey = sortkey;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


-- Correct actor.org_unit_ancestor_setting so that it returns
-- at most one setting value, rather than the entire set
-- of values defined for the OU and its ancestors.
--
INSERT INTO config.upgrade_log (version) VALUES ('0601');

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting( setting_name TEXT, org_id INT ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    cur_org INT;
BEGIN
    cur_org := org_id;
    LOOP
        SELECT INTO setting * FROM actor.org_unit_setting WHERE org_unit = cur_org AND name = setting_name;
        IF FOUND THEN
            RETURN NEXT setting;
            EXIT;
        END IF;
        SELECT INTO cur_org parent_ou FROM actor.org_unit WHERE id = cur_org;
        EXIT WHEN cur_org IS NULL;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql STABLE ROWS 1;


INSERT INTO config.upgrade_log (version) VALUES ('0602'); -- dbs via miker

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = rid AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.id)
                JOIN metabib.metarecord_source_map m ON (m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;   
                
    RETURN;     
END;            
$f$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = rid AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.id)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;   
                
    RETURN;     
END;            
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

-- Correct the fact that actor.org_unit_parent_protect() may not work
-- due to 'IF' conditions in PL/pgSQL not necessarily processing in the
-- order written
--
INSERT INTO config.upgrade_log (version) VALUES ('0605'); --dbwells via dbs

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


INSERT INTO config.upgrade_log (version) VALUES ('0607');

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT ou.* FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad USING (id) ORDER BY ouad.distance DESC;
$$ LANGUAGE SQL ROWS 1;

COMMIT;

