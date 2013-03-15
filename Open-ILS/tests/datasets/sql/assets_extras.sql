-- copy locations
-- copy location groups
-- copy stat cats
-- ...

INSERT INTO asset.copy_location (owning_lib, name) VALUES
(4, 'Adult'),
(4, 'Young Adult'),
(4, 'Juvenile'),
(4, 'AV'),
(4, 'Children''s AV'),
(5, 'Western'),
(5, 'Young Adult'),
(5, 'Genealogy'),
(5, 'Local History'),
(6, 'Sci-Fi'),
(6, 'Biography'),
(6, 'Ninjas'),
(6, 'Young Adult'),
(7, 'Vampires'),
(7, 'Western'),
(7, 'Young Adult'),
(7, 'Sports');

-- non-holable
INSERT INTO asset.copy_location (owning_lib, name, holdable) VALUES
(4, 'New Arrivals', FALSE);

-- non-holable, non-cirulcateable, non-visible
INSERT INTO asset.copy_location
    (owning_lib, name, holdable, opac_visible, circulate) VALUES
(5, 'Display', FALSE, FALSE, FALSE),
(6, 'Display', FALSE, FALSE, FALSE),
(7, 'Display', FALSE, FALSE, FALSE);


-- copy location groups

INSERT INTO asset.copy_location_group (name, owner) VALUES ('Sys1 Fiction', 2);

INSERT INTO asset.copy_location_group_map (lgroup, location)
    SELECT CURRVAL('asset.copy_location_group_id_seq'), id
        FROM asset.copy_location WHERE owning_lib in (4, 5)
        AND opac_visible;

INSERT INTO asset.copy_location_group (name, owner) VALUES ('Sys2 Fiction', 2);

INSERT INTO asset.copy_location_group_map (lgroup, location)
    SELECT CURRVAL('asset.copy_location_group_id_seq'), id
        FROM asset.copy_location WHERE owning_lib in (6, 7)
        AND opac_visible;

-- evenly distribute the copies across all of the copy locations.
-- there's probably a more effecient way, but this gets the job done

DO $$
    DECLARE cur_loc INTEGER;
    DECLARE cur_copy asset.copy%ROWTYPE;
BEGIN
    cur_copy := evergreen.next_copy(0);

    WHILE cur_copy.id IS NOT NULL LOOP
        FOR cur_loc IN SELECT id FROM asset.copy_location ORDER BY id LOOP
            UPDATE asset.copy SET location = cur_loc WHERE id = cur_copy.id;
            cur_copy := evergreen.next_copy(cur_copy.id);
            EXIT WHEN cur_copy.id IS NULL;
        END LOOP;
    END LOOP;
END $$;
