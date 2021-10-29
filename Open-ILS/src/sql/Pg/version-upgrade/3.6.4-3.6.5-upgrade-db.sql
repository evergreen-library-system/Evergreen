--Upgrade Script for 3.6.4 to 3.6.5
\set eg_version '''3.6.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.6.5', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1266', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.copies', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.copies',
        'Grid Config: eg.grid.catalog.record.copies',
        'cwst', 'label')
    );


SELECT evergreen.upgrade_deps_block_check('1268', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staff.catalog.results.show_more', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staff.catalog.results.show_more',
        'Show more details in Angular staff catalog',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1269', :eg_version);

WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('VIEW_BOOKING_RESERVATION', 'VIEW_BOOKING_RESERVATION_ATTR_MAP'))

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map
        
        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)
            
        --- Anybody who can view resources should also see reservations
        --- at the same level
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'VIEW_BOOKING_RESOURCE'
        );



SELECT evergreen.upgrade_deps_block_check('1270', :eg_version);

INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'BKS', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'COM', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MAP', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MIX', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'REC', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SCO', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SER', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'VIS', 39, 1, ' ');


INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('srce','Srce','Srce');

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(1750, 'srce', ' ', oils_i18n_gettext('1750', 'National bibliographic agency', 'ccvm', 'value')),
(1751, 'srce', 'c', oils_i18n_gettext('1751', 'Cooperative cataloging program', 'ccvm', 'value')),
(1752, 'srce', 'd', oils_i18n_gettext('1752', 'Other', 'ccvm', 'value'));


SELECT evergreen.upgrade_deps_block_check('1272', :eg_version);

DO $$
BEGIN

  PERFORM FROM config.usr_setting_type WHERE name = 'circ.collections.exempt';

  IF NOT FOUND THEN

    INSERT INTO config.usr_setting_type (
      name,
      opac_visible,
      label,
      description,
      datatype,
      reg_default
    ) VALUES (
      'circ.collections.exempt',
      FALSE,
      oils_i18n_gettext(
        'circ.collections.exempt',
        'Collections: Exempt',
        'cust',
        'label'
      ),
      oils_i18n_gettext(
        'circ.collections.exempt',
        'User is exempt from collections tracking/processing',
        'cust',
        'description'
      ),
      'bool',
      'false'
    );

  END IF;

END
$$;


SELECT evergreen.upgrade_deps_block_check('1279', :eg_version);

UPDATE config.org_unit_setting_type SET fm_class='cnal', datatype='link' WHERE name='ui.patron.default_inet_access_level';



SELECT evergreen.upgrade_deps_block_check('1283', :eg_version); -- rhamby/ehardy/jboyer

UPDATE asset.call_number SET record = -1 WHERE id = -1 AND record != -1;

CREATE RULE protect_bre_id_neg1 AS ON UPDATE TO biblio.record_entry WHERE OLD.id = -1 DO INSTEAD NOTHING;
CREATE RULE protect_acl_id_1 AS ON UPDATE TO asset.copy_location WHERE OLD.id = 1 DO INSTEAD NOTHING;
CREATE RULE protect_acn_id_neg1 AS ON UPDATE TO asset.call_number WHERE OLD.id = -1 DO INSTEAD NOTHING;

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

    -- we don't merge bib -1 
    IF target_record = -1 OR source_record = -1 THEN 
       RETURN 0;
    END IF;

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
    SELECT    INTO metarec *
      FROM    metabib.metarecord
      WHERE    master_record = source_record;

    IF FOUND THEN
        UPDATE    metabib.metarecord
          SET    master_record = target_record,
            mods = NULL
          WHERE    id = metarec.id;

        moved_objects := moved_objects + 1;
    END IF;

    -- Find call numbers attached to the source ...
    FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

        SELECT    INTO target_cn *
          FROM    asset.call_number
          WHERE    label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
            AND owning_lib = source_cn.owning_lib
            AND record = target_record
            AND NOT deleted;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copies to that, and ...
            UPDATE    asset.copy
              SET    call_number = target_cn.id
              WHERE    call_number = source_cn.id;

            -- ... move V holds to the move-target call number
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
        
                UPDATE    action.hold_request
                  SET    target = target_cn.id
                  WHERE    id = hold.id;
        
                moved_objects := moved_objects + 1;
            END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

        -- ... if not ...
        ELSE
            -- ... just move the call number to the target record
            UPDATE    asset.call_number
              SET    record = target_record
              WHERE    id = source_cn.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find T holds targeting the source record ...
    FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

        -- ... and move them to the target record
        UPDATE    action.hold_request
          SET    target = target_record
          WHERE    id = hold.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial records targeting the source record ...
    FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    serial.record_entry
          SET    record = target_record
          WHERE    id = ser_rec.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial subscriptions targeting the source record ...
    FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
        -- ... and move them to the target record
        UPDATE    serial.subscription
          SET    record_entry = target_record
          WHERE    id = ser_sub.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find booking resource types targeting the source record ...
    FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    booking.resource_type
          SET    record = target_record
          WHERE    id = booking.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find acq lineitems targeting the source record ...
    FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
        -- ... and move them to the target record
        UPDATE    acq.lineitem
          SET    eg_bib_id = target_record
          WHERE    id = acq_lineitem.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find acq user purchase requests targeting the source record ...
    FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
        -- ... and move them to the target record
        UPDATE    acq.user_request
          SET    eg_bib = target_record
          WHERE    id = acq_request.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find parts attached to the source ...
    FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

        SELECT    INTO target_part *
          FROM    biblio.monograph_part
          WHERE    label = source_part.label
            AND record = target_record;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copy-part maps to that, and ...
            UPDATE    asset.copy_part_map
              SET    part = target_part.id
              WHERE    part = source_part.id;

            -- ... move P holds to the move-target part
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
        
                UPDATE    action.hold_request
                  SET    target = target_part.id
                  WHERE    id = hold.id;
        
                moved_objects := moved_objects + 1;
            END LOOP;

        -- ... if not ...
        ELSE
            -- ... just move the part to the target record
            UPDATE    biblio.monograph_part
              SET    record = target_record
              WHERE    id = source_part.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find multi_home items attached to the source ...
    FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    biblio.peer_bib_copy_map
          SET    peer_record = target_record
          WHERE    id = multi_home.id;

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




SELECT evergreen.upgrade_deps_block_check('1294', :eg_version); -- mmorgan / tlittle / JBoyer

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.container.carousel_org_unit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.container.carousel_org_unit',
        'Grid Config: eg.grid.admin.local.container.carousel_org_unit',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.container.carousel', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.container.carousel',
        'Grid Config: eg.grid.admin.container.carousel',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.carousel_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.carousel_type',
        'Grid Config: eg.grid.admin.server.config.carousel_type',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1302', :eg_version);

UPDATE config.org_unit_setting_type
    SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.longoverdue';

UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.lost';

UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.claimsreturned';


SELECT evergreen.upgrade_deps_block_check('1303', :eg_version);

DROP INDEX authority.authority_full_rec_value_index;
CREATE INDEX authority_full_rec_value_index ON authority.full_rec (SUBSTRING(value FOR 1024));

DROP INDEX authority.authority_full_rec_value_tpo_index;
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (SUBSTRING(value FOR 1024) text_pattern_ops);


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
