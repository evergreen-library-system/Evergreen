-- copy locations
-- copy location groups
-- copy stat cats
-- ...

INSERT INTO asset.copy_location (owning_lib, name) VALUES
(2, 'Fiction'),
(3, 'Fiction'),
(2, 'Non-Fiction'),
(3, 'Non-Fiction'),
(2, 'Young Adult Fiction'),
(4, 'Young Adult Fiction'),
(5, 'Young Adult Fiction'),
(6, 'Young Adult Fiction'),
(2, 'Children''s Fiction'),
(3, 'Children''s Fiction'),
(4, 'Audio/Video'),
(5, 'Audio/Video'),
(5, 'Music'),
(6, 'Music'),
(6, 'Audio/Video'),
(4, 'Science Fiction'),
(7, 'Science Fiction'),
(5, 'Genealogy'),
(6, 'Genealogy'),
(4, 'Biography'),
(5, 'Biography'),
(6, 'Local History'),
(7, 'Local History');


-- different settings per org level
INSERT INTO asset.copy_location
    (owning_lib, name, holdable, opac_visible, circulate) VALUES
(2, 'Display', FALSE, FALSE, TRUE),
(4, 'Display', FALSE, FALSE, FALSE),
(5, 'Display', TRUE, FALSE, FALSE),
(6, 'Display', TRUE, FALSE, FALSE),
(7, 'Display', FALSE, FALSE, FALSE),
(1, 'New Arrivals', TRUE, TRUE, TRUE),
(2, 'New Arrivals', FALSE, TRUE, TRUE),
(4, 'New Arrivals', TRUE, TRUE, FALSE),
(5, 'New Arrivals', TRUE, TRUE, TRUE);

-- copy location groups

INSERT INTO asset.copy_location_group (name, owner) VALUES ('Sys1 Fiction', 2);

INSERT INTO asset.copy_location_group_map (lgroup, location)
    SELECT CURRVAL('asset.copy_location_group_id_seq'), id
        FROM asset.copy_location 
        WHERE owning_lib in (2, 4, 5) AND opac_visible;

INSERT INTO asset.copy_location_group (name, owner) VALUES ('Sys2 Fiction', 2);

INSERT INTO asset.copy_location_group_map (lgroup, location)
    SELECT CURRVAL('asset.copy_location_group_id_seq'), id
        FROM asset.copy_location 
        WHERE owning_lib in (3, 6, 7) AND opac_visible;

-- Distribute copies evenly across copy locations whose owning_lib
-- matches the copy circ lib.  To provide some level of repeatable
-- outcome, we loop instead of applying locations at randon within
-- a given owning_lib.
DO $$
    DECLARE cur_loc INTEGER;
    DECLARE cur_copy asset.copy%ROWTYPE;
BEGIN
    cur_loc := 0;

    FOR cur_copy IN SELECT * FROM asset.copy 
            WHERE location = 1 ORDER BY circ_lib, id LOOP

        -- find the next location for the current copy's circ lib
        SELECT INTO cur_loc id FROM asset.copy_location 
            WHERE owning_lib = cur_copy.circ_lib AND id > cur_loc 
            ORDER BY id LIMIT 1;

        IF NOT FOUND THEN
            -- start back over at the front of the list
            cur_loc := 0;
            SELECT INTO cur_loc id FROM asset.copy_location 
                WHERE owning_lib = cur_copy.circ_lib AND id > cur_loc 
                ORDER BY id LIMIT 1;
        END IF;

        IF NOT FOUND THEN
            -- no copy location at this circ lib, leave the default (1)
            CONTINUE;
        END IF;

        UPDATE asset.copy SET location = cur_loc WHERE id = cur_copy.id;
    END LOOP;
END $$;

