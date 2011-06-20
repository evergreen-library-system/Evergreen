-- Evergreen DB patch 0559.schema.biblio.extract_located_uris.sql
--
-- * Add a stored procedure to reingest problematic URIs
-- * Avoid duplicate row issues in biblio.extract_located_uris
-- * Fix LP 797304 and 797307 - asset.uri parsing bugs
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0559', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
CREATE OR REPLACE FUNCTION biblio.extract_located_uris( bib_id BIGINT, marcxml TEXT, editor_id INT ) RETURNS VOID AS $func$
DECLARE
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner_list  TEXT[];
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;
BEGIN

    -- Clear any URI mappings and call numbers for this bib.
    -- This leads to acn / auricnm inflation, but also enables
    -- old acn/auricnm's to go away and for bibs to be deleted.
    FOR uri_cn_id IN SELECT id FROM asset.call_number WHERE record = bib_id AND label = '##URI##' AND NOT deleted LOOP
        DELETE FROM asset.uri_call_number_map WHERE call_number = uri_cn_id;
        DELETE FROM asset.call_number WHERE id = uri_cn_id;
    END LOOP;

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()',uri_xml))[1];
            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];

            IF uri_label IS NULL THEN
                uri_label := uri_href;
            END IF;
            CONTINUE WHEN uri_href IS NULL;

            -- Get the distinct list of libraries wanting to use 
            SELECT  ARRAY_ACCUM(
                        DISTINCT REGEXP_REPLACE(
                            x,
                            $re$^.*?\((\w+)\).*$$re$,
                            E'\\1'
                        )
                    ) INTO uri_owner_list
              FROM  UNNEST(
                        oils_xpath(
                            '//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',
                            uri_xml
                        )
                    )x;

            IF ARRAY_UPPER(uri_owner_list,1) > 0 THEN

                -- look for a matching uri
                IF uri_use IS NULL THEN
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active;
                    END IF;
                ELSE
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                    END IF;
                END IF;

                FOR j IN 1 .. ARRAY_UPPER(uri_owner_list, 1) LOOP
                    uri_owner := uri_owner_list[j];

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
                    CONTINUE WHEN NOT FOUND;

                    -- we need a call number to link through
                    SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    IF NOT FOUND THEN
                        INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                            VALUES (uri_owner_id, bib_id, 'now', 'now', editor_id, editor_id, '##URI##');
                        SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    END IF;

                    -- now, link them if they're not already
                    SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    IF NOT FOUND THEN
                        INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
                    END IF;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.reingest_uris() RETURNS VOID AS $func$
DECLARE
    rec_id BIGINT;
BEGIN
    -- Get the distinct set of record IDs that need to be reingested
    -- (assuming that href = label is a reasonable red flag)
    FOR rec_id IN SELECT rec_uris.id FROM (
        SELECT acn.record AS id
            FROM asset.call_number acn
                INNER JOIN asset.uri_call_number_map auricnm ON auricnm.call_number = acn.id
                INNER JOIN asset.uri auri ON auri.id = auricnm.uri
                INNER JOIN biblio.record_entry bre ON acn.record = bre.id
            WHERE auri.href = auri.label
                AND xml_is_well_formed(bre.marc)
            GROUP BY acn.record
            ORDER BY acn.record
        ) AS rec_uris
    LOOP
        -- Reingest the offending records
        PERFORM biblio.extract_located_uris(rec_id, bre.marc, 1)
            FROM biblio.record_entry bre
            WHERE bre.id = rec_id;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-- Kick off the reingest; this may take a while
SELECT biblio.reingest_uris();


COMMIT;
