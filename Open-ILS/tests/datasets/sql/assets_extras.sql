-- copy locations
-- copy location groups
-- copy stat cats
-- ...

-- TODO:
-- This applies locations to copies without regard for the type
-- of record of each copy.  This leads to nonsensical copy / location 
-- pairings.  (E.g. a violin concerto copy with a "Newspapers" location).  
-- An improvement would be to create locations first, then select
-- locations for copies as they are inserted.  Time will tell if there will
-- ever be a large enough variety of data to do this in a meaningful way.
-- Also, it's kind of a pain, so, maybe later..

INSERT INTO asset.copy_location (owning_lib, name) VALUES
(1, 'Reference'),
(4, 'Reference'),
(4, 'Easy Reader'),
(5, 'Easy Reader'),
(6, 'Easy Reader'),
(2, 'Fiction'),
(3, 'Fiction'),
(2, 'Non-Fiction'),
(3, 'Non-Fiction'),
(2, 'Juvenile Non-Fiction'),
(3, 'Juvenile Non-Fiction'),
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
(7, 'Local History'),
(6, 'Federal Documents');


-- non-holdable, non-circulating
INSERT INTO asset.copy_location 
    (owning_lib, name, holdable, circulate) VALUES
(4, 'Periodicals', FALSE, FALSE),
(6, 'Periodicals', FALSE, FALSE),
(5, 'Magazines', FALSE, FALSE),
(7, 'Magazines', FALSE, FALSE),
(4, 'Newspapers', FALSE, FALSE);

-- non-holdable
INSERT INTO asset.copy_location (owning_lib, name, holdable) VALUES
(4, 'Reserves', FALSE),
(5, 'Reserves', FALSE),
(3, 'Reserves', FALSE),
(5, 'Theses', FALSE),
(7, 'Theses', TRUE),
(2, 'Special Collections', FALSE),
(6, 'Special Collections', FALSE),
(7, 'Special Collections', FALSE);


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

INSERT INTO asset.copy_location_group (name, owner) 
    VALUES ('Juvenile Collection', 2);

INSERT INTO asset.copy_location_group_map (lgroup, location)
    SELECT CURRVAL('asset.copy_location_group_id_seq'), id
        FROM asset.copy_location 
        WHERE owning_lib IN (2, 4, 5) AND 
            opac_visible AND 
            name IN (
                'Young Adult Fiction', 
                'Children''s Fiction',
                'Easy Reader', 
                'Juvenile Non-Fiction'
            );

INSERT INTO asset.copy_location_group (name, owner) 
    VALUES ('Local Interest Collection', 3);

INSERT INTO asset.copy_location_group_map (lgroup, location)
    SELECT CURRVAL('asset.copy_location_group_id_seq'), id
        FROM asset.copy_location 
        WHERE owning_lib IN (3, 6, 7) AND 
            opac_visible AND
            name IN (
                'Geneology',
                'Special Collections',
                'Local History'
            );

-- Distribute copies evenly across copy locations whose owning_lib
-- matches the copy circ lib.  To provide some level of repeatable
-- outcome, we loop instead of applying locations at randon within
-- a given owning_lib.
DO $$
    DECLARE cur_loc INTEGER;
    DECLARE cur_copy asset.copy%ROWTYPE;
    DECLARE cur_cn INTEGER;
BEGIN
    cur_loc := 0;
    cur_cn := 0;

    FOR cur_copy IN SELECT * FROM asset.copy 
            WHERE location = 1 ORDER BY circ_lib, call_number, id LOOP

        -- Move to the next copy location if we are changing call numbers.
        -- This provides some visual consistency between call numbers and
        -- copy locations and helps avoid having practically every copy in
        -- view residing in a different location.
        IF cur_cn <> cur_copy.call_number THEN

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

            cur_cn := cur_copy.call_number;
        END IF;

        UPDATE asset.copy SET location = cur_loc WHERE id = cur_copy.id;
    END LOOP;
END $$;

UPDATE asset.copy SET location = 1 WHERE id = 2905;
