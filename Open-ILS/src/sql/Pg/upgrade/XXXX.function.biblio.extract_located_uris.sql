BEGIN;

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
    current_uri     INT;
    current_map     INT;
    uri_map_count   INT;
    current_uri_map_list    INT[];
    current_map_owner_list  INT[];

BEGIN

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
            SELECT  ARRAY_AGG(
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

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = BTRIM(REPLACE(uri_owner,chr(160),''));
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
                        SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    END IF;

                    current_uri_map_list := current_uri_map_list || uri_map_id;
                    current_map_owner_list := current_map_owner_list || uri_cn_id;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    -- Clear any orphaned URIs, URI mappings and call
    -- numbers for this bib that weren't mapped above.
    FOR current_map IN
        SELECT  m.id
          FROM  asset.uri_call_number_map m
                LEFT JOIN asset.call_number cn ON (cn.id = m.call_number)
          WHERE cn.record = bib_id
                AND cn.label = '##URI##'
                AND (NOT (m.id = ANY (current_uri_map_list))
                     OR current_uri_map_list is NULL)
    LOOP
        SELECT uri INTO current_uri FROM asset.uri_call_number_map WHERE id = current_map;
        DELETE FROM asset.uri_call_number_map WHERE id = current_map;

        SELECT COUNT(*) INTO uri_map_count FROM asset.uri_call_number_map WHERE uri = current_uri;
        IF uri_map_count = 0 THEN
            DELETE FROM asset.uri WHERE id = current_uri;
        END IF;
    END LOOP;

    UPDATE asset.call_number
    SET deleted = TRUE, edit_date = now(), editor = editor_id
    WHERE id IN (
        SELECT  id
          FROM  asset.call_number
          WHERE record = bib_id
                AND label = '##URI##'
                AND NOT deleted
                AND (NOT (id = ANY (current_map_owner_list))
                     OR current_map_owner_list is NULL)
    );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- Remove existing orphaned URIs from the database.
DELETE FROM asset.uri
WHERE id IN
(
SELECT uri.id
FROM asset.uri
LEFT JOIN asset.uri_call_number_map
ON uri_call_number_map.uri = uri.id
LEFT JOIN serial.item
ON item.uri = uri.id
WHERE uri_call_number_map IS NULL
AND item IS NULL
);

COMMIT;

