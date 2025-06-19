BEGIN;

SELECT evergreen.upgrade_deps_block_check('1473', :eg_version);

-- Basically the same thing as using cascade update, but the stat_cat_entry isn't a foreign key as it can be freetext
CREATE OR REPLACE FUNCTION actor.stat_cat_entry_usr_map_cascade_update() RETURNS TRIGGER AS $$
BEGIN
    UPDATE actor.stat_cat_entry_usr_map
    SET stat_cat_entry = NEW.value
    WHERE stat_cat_entry = OLD.value
        AND stat_cat = OLD.stat_cat;
        
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


DROP TRIGGER IF EXISTS actor_stat_cat_entry_update_trigger ON actor.stat_cat_entry;
CREATE TRIGGER actor_stat_cat_entry_update_trigger
    BEFORE UPDATE ON actor.stat_cat_entry FOR EACH ROW
    EXECUTE FUNCTION actor.stat_cat_entry_usr_map_cascade_update();


-- Basically the same thing as using cascade delete, but the stat_cat_entry isn't a foreign key as it can be freetext
CREATE OR REPLACE FUNCTION actor.stat_cat_entry_usr_map_cascade_delete() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM actor.stat_cat_entry_usr_map
    WHERE stat_cat_entry = OLD.value
        AND stat_cat = OLD.stat_cat;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS actor_stat_cat_entry_delete_trigger ON actor.stat_cat_entry;
CREATE TRIGGER actor_stat_cat_entry_delete_trigger
    AFTER DELETE ON actor.stat_cat_entry FOR EACH ROW
    EXECUTE FUNCTION actor.stat_cat_entry_usr_map_cascade_delete();


COMMIT;
