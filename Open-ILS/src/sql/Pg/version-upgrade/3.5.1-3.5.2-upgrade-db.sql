--Upgrade Script for 3.5.1 to 3.5.2
\set eg_version '''3.5.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.5.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1214', :eg_version);

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

    -- Apply merge tracking
    UPDATE biblio.record_entry 
        SET merge_date = NOW() WHERE id = target_record;

    UPDATE biblio.record_entry
        SET merge_date = NOW(), merged_to = target_record
        WHERE id = source_record;

    -- replace book bag entries of source_record with target_record
    UPDATE container.biblio_record_entry_bucket_item
        SET target_biblio_record_entry = target_record
        WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'bookbag')
        AND target_biblio_record_entry = source_record;

    -- Finally, "delete" the source record
    UPDATE biblio.record_entry SET active = FALSE WHERE id = source_record;
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1215', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.cat.catalog.wide_holds', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.cat.catalog.wide_holds',
        'Default org unit for catalog holds org unit selector',
        'cwst', 'label'
    )
);




SELECT evergreen.upgrade_deps_block_check('1228', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT ) RETURNS SETOF actor.org_unit AS $$
    SELECT  aou.*
      FROM  actor.org_unit AS aou
            JOIN (
                (SELECT au.id, t.depth FROM actor.org_unit_ancestors($1) AS au JOIN actor.org_unit_type t ON (au.ou_type = t.id))
                    UNION
                (SELECT au.id, t.depth FROM actor.org_unit_descendants($1) AS au JOIN actor.org_unit_type t ON (au.ou_type = t.id))
            ) AS ad ON (aou.id=ad.id)
      ORDER BY ad.depth;
$$ LANGUAGE SQL STABLE;



INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1236', :eg_version);

CREATE OR REPLACE VIEW action.all_circulation_combined_types AS
 SELECT acirc.id AS id,
    acirc.xact_start,
    acirc.circ_lib,
    acirc.circ_staff,
    acirc.create_time,
    ac_acirc.circ_modifier AS item_type,
    'regular_circ'::text AS circ_type
   FROM action.circulation acirc,
    asset.copy ac_acirc
  WHERE acirc.target_copy = ac_acirc.id
UNION ALL
 SELECT ancc.id::BIGINT AS id,
    ancc.circ_time AS xact_start,
    ancc.circ_lib,
    ancc.staff AS circ_staff,
    ancc.circ_time AS create_time,
    cnct_ancc.name AS item_type,
    'non-cat_circ'::text AS circ_type
   FROM action.non_cataloged_circulation ancc,
    config.non_cataloged_type cnct_ancc
  WHERE ancc.item_type = cnct_ancc.id
UNION ALL
 SELECT aihu.id::BIGINT AS id,
    aihu.use_time AS xact_start,
    aihu.org_unit AS circ_lib,
    aihu.staff AS circ_staff,
    aihu.use_time AS create_time,
    ac_aihu.circ_modifier AS item_type,
    'in-house_use'::text AS circ_type
   FROM action.in_house_use aihu,
    asset.copy ac_aihu
  WHERE aihu.item = ac_aihu.id
UNION ALL
 SELECT ancihu.id::BIGINT AS id,
    ancihu.use_time AS xact_start,
    ancihu.org_unit AS circ_lib,
    ancihu.staff AS circ_staff,
    ancihu.use_time AS create_time,
    cnct_ancihu.name AS item_type,
    'non-cat-in-house_use'::text AS circ_type
   FROM action.non_cat_in_house_use ancihu,
    config.non_cataloged_type cnct_ancihu
  WHERE ancihu.item_type = cnct_ancihu.id
UNION ALL
 SELECT aacirc.id AS id,
    aacirc.xact_start,
    aacirc.circ_lib,
    aacirc.circ_staff,
    aacirc.create_time,
    ac_aacirc.circ_modifier AS item_type,
    'aged_circ'::text AS circ_type
   FROM action.aged_circulation aacirc,
    asset.copy ac_aacirc
  WHERE aacirc.target_copy = ac_aacirc.id;



SELECT evergreen.upgrade_deps_block_check('1238', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 625, 'VIEW_BOOKING_RESERVATION', oils_i18n_gettext(625,
    'View booking reservations', 'ppl', 'description')),
 ( 626, 'VIEW_BOOKING_RESERVATION_ATTR_MAP', oils_i18n_gettext(626,
    'View booking reservation attribute maps', 'ppl', 'description'))
;


SELECT evergreen.upgrade_deps_block_check('1239', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.booking.pull_list', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pull_list',
        'Grid Config: Booking Pull List',
        'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1241', :eg_version);

SET CONSTRAINTS ALL IMMEDIATE; -- to address "pending trigger events" error

-- Dedupe the table before applying the script.  Preserve the original to allow the admin to delete it manually later.
CREATE TABLE reporter.schedule_original (LIKE reporter.schedule);
INSERT INTO reporter.schedule_original SELECT * FROM reporter.schedule;
TRUNCATE reporter.schedule;
INSERT INTO reporter.schedule (SELECT DISTINCT ON (report, folder, runner, run_time) id, report, folder, runner, run_time, start_time, complete_time, email, excel_format, html_format, csv_format, chart_pie, chart_bar, chart_line, error_code, error_text FROM reporter.schedule_original);
\qecho NOTE: This has created a backup of the original reporter.schedule
\qecho table, named reporter.schedule_original.  Once you are sure that everything
\qecho works as expected, you can delete that table by issuing the following:
\qecho
\qecho  'DROP TABLE reporter.schedule_original;'
\qecho

-- Explicitly supply the name because it is referenced in clark-kent.pl
CREATE UNIQUE INDEX rpt_sched_recurrence_once_idx ON reporter.schedule (report,folder,runner,run_time,COALESCE(email,''));



-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1242', :eg_version);

-- Long Overdue
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.longoverdue';

-- Lost
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.lost';

-- Claims Returned
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.claimsreturned';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
