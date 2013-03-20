--Upgrade Script for 2.2.6 to 2.2.7
\set eg_version '''2.2.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.7', :eg_version);
-- Evergreen DB patch XXXX.function.merge_record_assets_deleted_call_numbers.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0761', :eg_version);

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
                        array_to_string(
                            array_accum(
                                '<subfield code="' || subfield || '">' ||
                                regexp_replace(
                                    regexp_replace(
                                        regexp_replace(data,'&','&amp;','g'),
                                        '>', '&gt;', 'g'
                                    ),
                                    '<', '&lt;', 'g'
                                ) || '</subfield>'
                            ), ''
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


SELECT evergreen.upgrade_deps_block_check('0764', :eg_version);

UPDATE config.z3950_source
    SET host = 'lx2.loc.gov', port = 210, db = 'LCDB'
    WHERE name = 'loc'
        AND host = 'z3950.loc.gov'
        AND port = 7090
        AND db = 'Voyager';

UPDATE config.z3950_attr
    SET format = 6
    WHERE source = 'loc'
        AND name = 'lccn'
        AND format = 1;



SELECT evergreen.upgrade_deps_block_check('0770', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.get_barcodes(select_ou INT, type TEXT, in_barcode TEXT) RETURNS SETOF evergreen.barcode_set AS $$
DECLARE
    cur_barcode TEXT;
    barcode_len INT;
    completion_len  INT;
    asset_barcodes  TEXT[];
    actor_barcodes  TEXT[];
    do_asset    BOOL = false;
    do_serial   BOOL = false;
    do_booking  BOOL = false;
    do_actor    BOOL = false;
    completion_set  config.barcode_completion%ROWTYPE;
BEGIN

    IF position('asset' in type) > 0 THEN
        do_asset = true;
    END IF;
    IF position('serial' in type) > 0 THEN
        do_serial = true;
    END IF;
    IF position('booking' in type) > 0 THEN
        do_booking = true;
    END IF;
    IF do_asset OR do_serial OR do_booking THEN
        asset_barcodes = asset_barcodes || in_barcode;
    END IF;
    IF position('actor' in type) > 0 THEN
        do_actor = true;
        actor_barcodes = actor_barcodes || in_barcode;
    END IF;

    barcode_len := length(in_barcode);

    FOR completion_set IN
      SELECT * FROM config.barcode_completion
        WHERE active
        AND org_unit IN (SELECT aou.id FROM actor.org_unit_ancestors(select_ou) aou)
        LOOP
        IF completion_set.prefix IS NULL THEN
            completion_set.prefix := '';
        END IF;
        IF completion_set.suffix IS NULL THEN
            completion_set.suffix := '';
        END IF;
        IF completion_set.length = 0 OR completion_set.padding IS NULL OR length(completion_set.padding) = 0 THEN
            cur_barcode = completion_set.prefix || in_barcode || completion_set.suffix;
        ELSE
            completion_len = completion_set.length - length(completion_set.prefix) - length(completion_set.suffix);
            IF completion_len >= barcode_len THEN
                IF completion_set.padding_end THEN
                    cur_barcode = rpad(in_barcode, completion_len, completion_set.padding);
                ELSE
                    cur_barcode = lpad(in_barcode, completion_len, completion_set.padding);
                END IF;
                cur_barcode = completion_set.prefix || cur_barcode || completion_set.suffix;
            END IF;
        END IF;
        IF completion_set.actor THEN
            actor_barcodes = actor_barcodes || cur_barcode;
        END IF;
        IF completion_set.asset THEN
            asset_barcodes = asset_barcodes || cur_barcode;
        END IF;
    END LOOP;

    IF do_asset AND do_serial THEN
        RETURN QUERY SELECT 'asset'::TEXT, id, barcode FROM ONLY asset.copy WHERE barcode = ANY(asset_barcodes) AND deleted = false;
        RETURN QUERY SELECT 'serial'::TEXT, id, barcode FROM serial.unit WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    ELSIF do_asset THEN
        RETURN QUERY SELECT 'asset'::TEXT, id, barcode FROM asset.copy WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    ELSIF do_serial THEN
        RETURN QUERY SELECT 'serial'::TEXT, id, barcode FROM serial.unit WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    END IF;
    IF do_booking THEN
        RETURN QUERY SELECT 'booking'::TEXT, id::BIGINT, barcode FROM booking.resource WHERE barcode = ANY(asset_barcodes);
    END IF;
    IF do_actor THEN
        RETURN QUERY SELECT 'actor'::TEXT, c.usr::BIGINT, c.barcode FROM actor.card c JOIN actor.usr u ON c.usr = u.id WHERE
            ((c.barcode = ANY(actor_barcodes) AND c.active) OR c.barcode = in_barcode) AND NOT u.deleted ORDER BY usr;
    END IF;
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Evergreen DB patch 0783.schema.enforce_use_id_for_tcn.sql
--
-- Sets the TCN value in the biblio.record_entry row to bib ID,
-- if the appropriate setting is in place
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0783', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
CREATE OR REPLACE FUNCTION evergreen.maintain_901 () RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $schema = $_TD->{table_schema};
my $marc = MARC::Record->new_from_xml($_TD->{new}{marc});

my @old901s = $marc->field('901');
$marc->delete_fields(@old901s);

if ($schema eq 'biblio') {
    my $tcn_value = $_TD->{new}{tcn_value};

    # Set TCN value to record ID?
    my $id_as_tcn = spi_exec_query("
        SELECT enabled
        FROM config.global_flag
        WHERE name = 'cat.bib.use_id_for_tcn'
    ");
    if (($id_as_tcn->{processed}) && $id_as_tcn->{rows}[0]->{enabled} eq 't') {
        $tcn_value = $_TD->{new}{id}; 
        $_TD->{new}{tcn_value} = $tcn_value;
    }

    my $new_901 = MARC::Field->new("901", " ", " ",
        "a" => $tcn_value,
        "b" => $_TD->{new}{tcn_source},
        "c" => $_TD->{new}{id},
        "t" => $schema
    );

    if ($_TD->{new}{owner}) {
        $new_901->add_subfields("o" => $_TD->{new}{owner});
    }

    if ($_TD->{new}{share_depth}) {
        $new_901->add_subfields("d" => $_TD->{new}{share_depth});
    }

    $marc->append_fields($new_901);
} elsif ($schema eq 'authority') {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
    );
    $marc->append_fields($new_901);
} elsif ($schema eq 'serial') {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
        "o" => $_TD->{new}{owning_lib},
    );

    if ($_TD->{new}{record}) {
        $new_901->add_subfields("r" => $_TD->{new}{record});
    }

    $marc->append_fields($new_901);
} else {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
    );
    $marc->append_fields($new_901);
}

my $xml = $marc->as_xml_record();
$xml =~ s/\n//sgo;
$xml =~ s/^<\?xml.+\?\s*>//go;
$xml =~ s/>\s+</></go;
$xml =~ s/\p{Cc}//go;

# Embed a version of OpenILS::Application::AppUtils->entityize()
# to avoid having to set PERL5LIB for PostgreSQL as well

# If we are going to convert non-ASCII characters to XML entities,
# we had better be dealing with a UTF8 string to begin with
$xml = decode_utf8($xml);

$xml = NFC($xml);

# Convert raw ampersands to entities
$xml =~ s/&(?!\S+;)/&amp;/gso;

# Convert Unicode characters to entities
$xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

$xml =~ s/[\x00-\x1f]//go;
$_TD->{new}{marc} = $xml;

return "MODIFY";
$func$ LANGUAGE PLPERLU;


COMMIT;
