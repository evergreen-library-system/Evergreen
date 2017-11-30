--Upgrade Script for 2.12.7 to 2.12.8
\set eg_version '''2.12.8'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.12.8', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1079', :eg_version); -- rhamby/cesardv/gmcharlt

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
			' tag="856"' ||
			' ind1="' || FIRST(ind1) || '"'  ||
			' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

	-- Find and move metarecords to the target record
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
			AND owning_lib = source_cn.owning_lib
			AND record = target_record
			AND NOT deleted;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial subscriptions targeting the source record ...
	FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.subscription
		  SET	record_entry = target_record
		  WHERE	id = ser_sub.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find booking resource types targeting the source record ...
	FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	booking.resource_type
		  SET	record = target_record
		  WHERE	id = booking.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq lineitems targeting the source record ...
	FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.lineitem
		  SET	eg_bib_id = target_record
		  WHERE	id = acq_lineitem.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq user purchase requests targeting the source record ...
	FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.user_request
		  SET	eg_bib = target_record
		  WHERE	id = acq_request.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find parts attached to the source ...
	FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

		SELECT	INTO target_part *
		  FROM	biblio.monograph_part
		  WHERE	label = source_part.label
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copy-part maps to that, and ...
			UPDATE	asset.copy_part_map
			  SET	part = target_part.id
			  WHERE	part = source_part.id;

			-- ... move P holds to the move-target part
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_part.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the part to the target record
			UPDATE	biblio.monograph_part
			  SET	record = target_record
			  WHERE	id = source_part.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find multi_home items attached to the source ...
	FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	biblio.peer_bib_copy_map
		  SET	peer_record = target_record
		  WHERE	id = multi_home.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- And delete mappings where the item's home bib was merged with the peer bib
	DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
		SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
		FROM asset.copy WHERE id = target_copy
	);

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

-- Evergreen DB patch XXXX.schema.qualify_unaccent_refs.sql
--
-- LP#1671150 Fix unaccent() function call in evergreen.unaccent_and_squash()
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1083', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
        BEGIN
        RETURN evergreen.lowercase(public.unaccent('public.unaccent', regexp_replace(arg, '[\s[:punct:]]','','g')));
        END;
$$ LANGUAGE PLPGSQL;

-- Drop indexes if present, so that we can re-create them
DROP INDEX IF EXISTS actor.actor_usr_first_given_name_unaccent_idx;
DROP INDEX IF EXISTS actor.actor_usr_second_given_name_unaccent_idx;
DROP INDEX IF EXISTS actor.actor_usr_family_name_unaccent_idx; 
DROP INDEX IF EXISTS actor.actor_usr_usrname_unaccent_idx; 

-- Create (or re-create) indexes -- they may be missing if pg_restore failed to create
-- them due to the previously unqualified call to unaccent()
CREATE INDEX actor_usr_first_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(first_given_name));
CREATE INDEX actor_usr_second_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(second_given_name));
CREATE INDEX actor_usr_family_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(family_name));
CREATE INDEX actor_usr_usrname_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(usrname));

COMMIT;
