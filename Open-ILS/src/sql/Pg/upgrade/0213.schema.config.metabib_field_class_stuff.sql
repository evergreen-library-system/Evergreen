
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0213');

CREATE TABLE config.metabib_class (
    name    TEXT    PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE
);

INSERT INTO config.metabib_class ( name, label ) VALUES ( 'keyword', oils_i18n_gettext('keyword', 'Keyword', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'title', oils_i18n_gettext('title', 'Title', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'author', oils_i18n_gettext('author', 'Author', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'subject', oils_i18n_gettext('subject', 'Subject', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'series', oils_i18n_gettext('series', 'Series', 'cmc', 'label') );

ALTER TABLE config.metabib_field ADD COLUMN label TEXT;
UPDATE config.metabib_field SET label = name;
ALTER TABLE config.metabib_field ALTER COLUMN label SET NOT NULL;

ALTER TABLE config.metabib_field ADD CONSTRAINT field_class_fkey FOREIGN KEY (field_class) REFERENCES config.metabib_class (name);

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM explode_array(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            curr_text := ARRAY_TO_STRING(
                oils_xpath( '//text()',
                    REGEXP_REPLACE( -- This escapes all &s not followed by "amp;".  Data ise returned from oils_xpath (above) in UTF-8, not entity encoded
                        REGEXP_REPLACE( -- This escapes embeded <s
                            xml_node,
                            $re$(>[^<]+)(<)([^>]+<)$re$,
                            E'\\1&lt;\\3',
                            'g'
                        ),
                        '&(?!amp;)',
                        '&amp;',
                        'g'
                    )
                ),
                ' '
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(curr_text, E'\\s+', ' ', 'g'));

                RETURN NEXT output_row;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            RETURN NEXT output_row;
        END IF;

    END LOOP;

END;
$func$ LANGUAGE PLPGSQL;


COMMIT;

