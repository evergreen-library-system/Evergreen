BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0816', :eg_version);

-- To avoid problems with altering a table column after doing an
-- update.
ALTER TABLE authority.control_set_authority_field
    DISABLE TRIGGER ALL;

ALTER TABLE authority.control_set_authority_field
    ADD COLUMN display_sf_list TEXT;

UPDATE authority.control_set_authority_field
    SET display_sf_list = REGEXP_REPLACE(sf_list, '[w254]', '', 'g');

ALTER TABLE authority.control_set_authority_field
    ALTER COLUMN display_sf_list SET NOT NULL;

ALTER TABLE authority.control_set_authority_field
    ENABLE TRIGGER ALL;

ALTER TABLE metabib.browse_entry_def_map
    ADD COLUMN authority BIGINT REFERENCES authority.record_entry (id)
        ON DELETE SET NULL;

ALTER TABLE config.metabib_field ADD COLUMN authority_xpath TEXT;
ALTER TABLE config.metabib_field ADD COLUMN browse_sort_xpath TEXT;

UPDATE config.metabib_field
    SET authority_xpath = '//@xlink:href'
    WHERE
        format = 'mods32' AND
        field_class IN ('subject','series','title','author') AND
        browse_field IS TRUE;

ALTER TYPE metabib.field_entry_template ADD ATTRIBUTE authority BIGINT;
ALTER TYPE metabib.field_entry_template ADD ATTRIBUTE sort_value TEXT;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
BEGIN

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            SELECT INTO mbe_row * FROM metabib.browse_entry
                WHERE value = value_prepped AND sort_value = ind_data.sort_value;

            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value );

                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
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
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
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

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.search_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
                output_row.sort_value := NULL;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;

$func$ LANGUAGE PLPGSQL;


-- 953.data.MODS32-xsl.sql
UPDATE config.xml_transform SET xslt=$$<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns="http://www.loc.gov/mods/v3" xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="xlink marc" version="1.0">
	<xsl:output encoding="UTF-8" indent="yes" method="xml"/>
<!--
Revision 1.14 - Fixed template isValid and fields 010, 020, 022, 024, 028, and 037 to output additional identifier elements 
  with corresponding @type and @invalid eq 'yes' when subfields z or y (in the case of 022) exist in the MARCXML ::: 2007/01/04 17:35:20 cred

Revision 1.13 - Changed order of output under cartographics to reflect schema  2006/11/28 tmee
	
Revision 1.12 - Updated to reflect MODS 3.2 Mapping  2006/10/11 tmee
		
Revision 1.11 - The attribute objectPart moved from <languageTerm> to <language>
      2006/04/08  jrad

Revision 1.10 MODS 3.1 revisions to language and classification elements  
				(plus ability to find marc:collection embedded in wrapper elements such as SRU zs: wrappers)
				2006/02/06  ggar

Revision 1.9 subfield $y was added to field 242 2004/09/02 10:57 jrad

Revision 1.8 Subject chopPunctuation expanded and attribute fixes 2004/08/12 jrad

Revision 1.7 2004/03/25 08:29 jrad

Revision 1.6 various validation fixes 2004/02/20 ntra

Revision 1.5  2003/10/02 16:18:58  ntra
MODS2 to MODS3 updates, language unstacking and 
de-duping, chopPunctuation expanded

Revision 1.3  2003/04/03 00:07:19  ntra
Revision 1.3 Additional Changes not related to MODS Version 2.0 by ntra

Revision 1.2  2003/03/24 19:37:42  ckeith
Added Log Comment

-->
	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="//marc:collection">
				<modsCollection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:collection/marc:record">
						<mods version="3.2">
							<xsl:call-template name="marcRecord"/>
						</mods>
					</xsl:for-each>
				</modsCollection>
			</xsl:when>
			<xsl:otherwise>
				<mods xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="3.2" xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:record">
						<xsl:call-template name="marcRecord"/>
					</xsl:for-each>
				</mods>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="marcRecord">
		<xsl:variable name="leader" select="marc:leader"/>
		<xsl:variable name="leader6" select="substring($leader,7,1)"/>
		<xsl:variable name="leader7" select="substring($leader,8,1)"/>
		<xsl:variable name="controlField008" select="marc:controlfield[@tag='008']"/>
		<xsl:variable name="typeOf008">
			<xsl:choose>
				<xsl:when test="$leader6='a'">
					<xsl:choose>
						<xsl:when test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'">BK</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'">SE</xsl:when>
					</xsl:choose>
				</xsl:when>
				<xsl:when test="$leader6='t'">BK</xsl:when>
				<xsl:when test="$leader6='p'">MM</xsl:when>
				<xsl:when test="$leader6='m'">CF</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">MP</xsl:when>
				<xsl:when test="$leader6='g' or $leader6='k' or $leader6='o' or $leader6='r'">VM</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d' or $leader6='i' or $leader6='j'">MU</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:for-each select="marc:datafield[@tag='245']">
			<titleInfo>
				<xsl:variable name="title">
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='b']">
							<xsl:call-template name="specialSubfieldSelect">
								<xsl:with-param name="axis">b</xsl:with-param>
								<xsl:with-param name="beforeCodes">afgk</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">abfgk</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="$title"/>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<xsl:choose>
					<xsl:when test="@ind2>0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind2)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind2+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop"/>
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:if test="marc:subfield[@code='b']">
					<subTitle>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="axis">b</xsl:with-param>
									<xsl:with-param name="anyCodes">b</xsl:with-param>
									<xsl:with-param name="afterCodes">afgk</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</subTitle>
				</xsl:if>
				<xsl:call-template name="part"></xsl:call-template>
			</titleInfo>
			<!-- A form of title that ignores non-filing characters; useful
				 for not converting "L'Oreal" into "L' Oreal" at index time -->
			<titleNonfiling>
				<xsl:variable name="title">
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='b']">
							<xsl:call-template name="specialSubfieldSelect">
								<xsl:with-param name="axis">b</xsl:with-param>
								<xsl:with-param name="beforeCodes">afgk</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">abfgk</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<title>
					<xsl:value-of select="$title"/>
				</title>
				<xsl:if test="marc:subfield[@code='b']">
					<subTitle>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="axis">b</xsl:with-param>
									<xsl:with-param name="anyCodes">b</xsl:with-param>
									<xsl:with-param name="afterCodes">afgk</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</subTitle>
				</xsl:if>
				<xsl:call-template name="part"></xsl:call-template>
			</titleNonfiling>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='210']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='242']">
			<xsl:variable name="titleChop">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<!-- 1/04 removed $h, b -->
							<xsl:with-param name="codes">a</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:variable>
			<titleInfo type="translated">
				<!--09/01/04 Added subfield $y-->
				<xsl:for-each select="marc:subfield[@code='y']">
					<xsl:attribute name="lang">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:value-of select="$titleChop" />
				</title>
				<!-- 1/04 fix -->
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
			<titleInfo type="translated-nfi">
				<xsl:for-each select="marc:subfield[@code='y']">
					<xsl:attribute name="lang">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<xsl:choose>
					<xsl:when test="@ind2>0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind2)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind2+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop" />
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='246']">
			<titleInfo type="alternative">
				<xsl:for-each select="marc:subfield[@code='i']">
					<xsl:attribute name="displayLabel">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, $b -->
								<xsl:with-param name="codes">af</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='130']|marc:datafield[@tag='240']|marc:datafield[@tag='730'][@ind2!='2']">
			<xsl:variable name="nfi">
				<xsl:choose>
					<xsl:when test="@tag='240'">
						<xsl:value-of select="@ind2"/>
					</xsl:when>
					<xsl:otherwise>
						<xsl:value-of select="@ind1"/>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:variable>
			<xsl:variable name="titleChop">
				<xsl:call-template name="uri" />
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield">
						<xsl:if test="(contains('adfklmor',@code) and (not(../marc:subfield[@code='n' or @code='p']) or (following-sibling::marc:subfield[@code='n' or @code='p'])))">
							<xsl:value-of select="text()"/>
							<xsl:text> </xsl:text>
						</xsl:if>
					</xsl:for-each>
				</xsl:variable>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:variable>
			<titleInfo type="uniform">
				<title>
					<xsl:value-of select="$titleChop"/>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
			<titleInfo type="uniform-nfi">
				<xsl:choose>
					<xsl:when test="$nfi>0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,$nfi)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,$nfi+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop"/>
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='740'][@ind2!='2']">
			<xsl:variable name="titleChop">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">ah</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:variable>
			<titleInfo type="alternative">
				<title>
					<xsl:value-of select="$titleChop" />
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
			<titleInfo type="alternative-nfi">
				<xsl:choose>
					<xsl:when test="@ind1>0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind1)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind1+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop" />
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='100']">
			<name type="personal">
				<xsl:call-template name="uri" />
				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='110']">
			<name type="corporate">
				<xsl:call-template name="uri" />
				<xsl:call-template name="nameABCDN"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='111']">
			<name type="conference">
				<xsl:call-template name="uri" />
				<xsl:call-template name="nameACDEQ"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='700'][not(marc:subfield[@code='t'])]">
			<name type="personal">
				<xsl:call-template name="uri" />
				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='710'][not(marc:subfield[@code='t'])]">
			<name type="corporate">
				<xsl:call-template name="uri" />
				<xsl:call-template name="nameABCDN"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='711'][not(marc:subfield[@code='t'])]">
			<name type="conference">
				<xsl:call-template name="uri" />
				<xsl:call-template name="nameACDEQ"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='720'][not(marc:subfield[@code='t'])]">
			<name>
				<xsl:if test="@ind1=1">
					<xsl:attribute name="type">
						<xsl:text>personal</xsl:text>
					</xsl:attribute>
				</xsl:if>
				<namePart>
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</namePart>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<typeOfResource>
			<xsl:if test="$leader7='c'">
				<xsl:attribute name="collection">yes</xsl:attribute>
			</xsl:if>
			<xsl:if test="$leader6='d' or $leader6='f' or $leader6='p' or $leader6='t'">
				<xsl:attribute name="manuscript">yes</xsl:attribute>
			</xsl:if>
			<xsl:choose>
				<xsl:when test="$leader6='a' or $leader6='t'">text</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">cartographic</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d'">notated music</xsl:when>
				<xsl:when test="$leader6='i'">sound recording-nonmusical</xsl:when>
				<xsl:when test="$leader6='j'">sound recording-musical</xsl:when>
				<xsl:when test="$leader6='k'">still image</xsl:when>
				<xsl:when test="$leader6='g'">moving image</xsl:when>
				<xsl:when test="$leader6='r'">three dimensional object</xsl:when>
				<xsl:when test="$leader6='m'">software, multimedia</xsl:when>
				<xsl:when test="$leader6='p'">mixed material</xsl:when>
			</xsl:choose>
		</typeOfResource>
		<xsl:if test="substring($controlField008,26,1)='d'">
			<genre authority="marc">globe</genre>
		</xsl:if>
		<xsl:if test="marc:controlfield[@tag='007'][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
			<genre authority="marc">remote sensing image</genre>
		</xsl:if>
		<xsl:if test="$typeOf008='MP'">
			<xsl:variable name="controlField008-25" select="substring($controlField008,26,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-25='a' or $controlField008-25='b' or $controlField008-25='c' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
					<genre authority="marc">map</genre>
				</xsl:when>
				<xsl:when test="$controlField008-25='e' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
					<genre authority="marc">atlas</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='SE'">
			<xsl:variable name="controlField008-21" select="substring($controlField008,22,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-21='d'">
					<genre authority="marc">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='l'">
					<genre authority="marc">loose-leaf</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='m'">
					<genre authority="marc">series</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='n'">
					<genre authority="marc">newspaper</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='p'">
					<genre authority="marc">periodical</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='w'">
					<genre authority="marc">web site</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK' or $typeOf008='SE'">
			<xsl:variable name="controlField008-24" select="substring($controlField008,25,4)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="contains($controlField008-24,'a')">
					<genre authority="marc">abstract or summary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'b')">
					<genre authority="marc">bibliography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'c')">
					<genre authority="marc">catalog</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'d')">
					<genre authority="marc">dictionary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'e')">
					<genre authority="marc">encyclopedia</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'f')">
					<genre authority="marc">handbook</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'g')">
					<genre authority="marc">legal article</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'i')">
					<genre authority="marc">index</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'k')">
					<genre authority="marc">discography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'l')">
					<genre authority="marc">legislation</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'m')">
					<genre authority="marc">theses</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'n')">
					<genre authority="marc">survey of literature</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'o')">
					<genre authority="marc">review</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'p')">
					<genre authority="marc">programmed text</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'q')">
					<genre authority="marc">filmography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'r')">
					<genre authority="marc">directory</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'s')">
					<genre authority="marc">statistics</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'t')">
					<genre authority="marc">technical report</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'v')">
					<genre authority="marc">legal case and case notes</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'w')">
					<genre authority="marc">law report or digest</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'z')">
					<genre authority="marc">treaty</genre>
				</xsl:when>
			</xsl:choose>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-29='1'">
					<genre authority="marc">conference publication</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='CF'">
			<xsl:variable name="controlField008-26" select="substring($controlField008,27,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-26='a'">
					<genre authority="marc">numeric data</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='e'">
					<genre authority="marc">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='f'">
					<genre authority="marc">font</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='g'">
					<genre authority="marc">game</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK'">
			<xsl:if test="substring($controlField008,25,1)='j'">
				<genre authority="marc">patent</genre>
			</xsl:if>
			<xsl:if test="substring($controlField008,31,1)='1'">
				<genre authority="marc">festschrift</genre>
			</xsl:if>
			<xsl:variable name="controlField008-34" select="substring($controlField008,35,1)"></xsl:variable>
			<xsl:if test="$controlField008-34='a' or $controlField008-34='b' or $controlField008-34='c' or $controlField008-34='d'">
				<genre authority="marc">biography</genre>
			</xsl:if>
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-33='e'">
					<genre authority="marc">essay</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marc">drama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marc">comic strip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marc">fiction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='h'">
					<genre authority="marc">humor, satire</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marc">letter</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marc">novel</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='j'">
					<genre authority="marc">short story</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marc">speech</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='MU'">
			<xsl:variable name="controlField008-30-31" select="substring($controlField008,31,2)"></xsl:variable>
			<xsl:if test="contains($controlField008-30-31,'b')">
				<genre authority="marc">biography</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'c')">
				<genre authority="marc">conference publication</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'d')">
				<genre authority="marc">drama</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'e')">
				<genre authority="marc">essay</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'f')">
				<genre authority="marc">fiction</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'o')">
				<genre authority="marc">folktale</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'h')">
				<genre authority="marc">history</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'k')">
				<genre authority="marc">humor, satire</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'m')">
				<genre authority="marc">memoir</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'p')">
				<genre authority="marc">poetry</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'r')">
				<genre authority="marc">rehearsal</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'g')">
				<genre authority="marc">reporting</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'s')">
				<genre authority="marc">sound</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'l')">
				<genre authority="marc">speech</genre>
			</xsl:if>
		</xsl:if>
		<xsl:if test="$typeOf008='VM'">
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-33='a'">
					<genre authority="marc">art original</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='b'">
					<genre authority="marc">kit</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marc">art reproduction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marc">diorama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marc">filmstrip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='g'">
					<genre authority="marc">legal article</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marc">picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='k'">
					<genre authority="marc">graphic</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marc">technical drawing</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='m'">
					<genre authority="marc">motion picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='n'">
					<genre authority="marc">chart</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='o'">
					<genre authority="marc">flash card</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='p'">
					<genre authority="marc">microscope slide</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='q' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
					<genre authority="marc">model</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='r'">
					<genre authority="marc">realia</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marc">slide</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='t'">
					<genre authority="marc">transparency</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='v'">
					<genre authority="marc">videorecording</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='w'">
					<genre authority="marc">toy</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=655]">
			<genre authority="marc">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abvxyz</xsl:with-param>
					<xsl:with-param name="delimeter">-</xsl:with-param>
				</xsl:call-template>
			</genre>
		</xsl:for-each>
		<originInfo>
			<xsl:variable name="MARCpublicationCode" select="normalize-space(substring($controlField008,16,3))"></xsl:variable>
			<xsl:if test="translate($MARCpublicationCode,'|','')">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">marccountry</xsl:attribute>
						<xsl:value-of select="$MARCpublicationCode"/>
					</placeTerm>
				</place>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=044]/marc:subfield[@code='c']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">iso3166</xsl:attribute>
						<xsl:value-of select="."/>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=260]/marc:subfield[@code='a']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">text</xsl:attribute>
						<xsl:call-template name="chopPunctuationFront">
							<xsl:with-param name="chopString">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."/>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='m']">
				<dateValid point="start">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='n']">
				<dateValid point="end">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='j']">
				<dateModified>
					<xsl:value-of select="."/>
				</dateModified>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=260]/marc:subfield[@code='b' or @code='c' or @code='g']">
				<xsl:choose>
					<xsl:when test="@code='b'">
						<publisher>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
								<xsl:with-param name="punctuation">
									<xsl:text>:,;/ </xsl:text>
								</xsl:with-param>
							</xsl:call-template>
						</publisher>
					</xsl:when>
					<xsl:when test="@code='c'">
						<dateIssued>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</dateIssued>
					</xsl:when>
					<xsl:when test="@code='g'">
						<dateCreated>
							<xsl:value-of select="."/>
						</dateCreated>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<xsl:variable name="dataField260c">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="marc:datafield[@tag=260]/marc:subfield[@code='c']"></xsl:with-param>
				</xsl:call-template>
			</xsl:variable>
			<xsl:variable name="controlField008-7-10" select="normalize-space(substring($controlField008, 8, 4))"></xsl:variable>
			<xsl:variable name="controlField008-11-14" select="normalize-space(substring($controlField008, 12, 4))"></xsl:variable>
			<xsl:variable name="controlField008-6" select="normalize-space(substring($controlField008, 7, 1))"></xsl:variable>
			<xsl:if test="$controlField008-6='e' or $controlField008-6='p' or $controlField008-6='r' or $controlField008-6='t' or $controlField008-6='s'">
				<xsl:if test="$controlField008-7-10 and ($controlField008-7-10 != $dataField260c)">
					<dateIssued encoding="marc">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start" qualifier="questionable">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end" qualifier="questionable">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='t'">
				<xsl:if test="$controlField008-11-14">
					<copyrightDate encoding="marc">
						<xsl:value-of select="$controlField008-11-14"/>
					</copyrightDate>
				</xsl:if>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=0 or @ind1=1]/marc:subfield[@code='a']">
				<dateCaptured encoding="iso8601">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][1]">
				<dateCaptured encoding="iso8601" point="start">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][2]">
				<dateCaptured encoding="iso8601" point="end">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=250]/marc:subfield[@code='a']">
				<edition>
					<xsl:value-of select="."/>
				</edition>
			</xsl:for-each>
			<xsl:for-each select="marc:leader">
				<issuance>
					<xsl:choose>
						<xsl:when test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'">monographic</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'">continuing</xsl:when>
					</xsl:choose>
				</issuance>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=310]|marc:datafield[@tag=321]">
				<frequency>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">ab</xsl:with-param>
					</xsl:call-template>
				</frequency>
			</xsl:for-each>
		</originInfo>
		<xsl:variable name="controlField008-35-37" select="normalize-space(translate(substring($controlField008,36,3),'|#',''))"></xsl:variable>
		<xsl:if test="$controlField008-35-37">
			<language>
				<languageTerm authority="iso639-2b" type="code">
					<xsl:value-of select="substring($controlField008,36,3)"/>
				</languageTerm>
			</language>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=041]">
			<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='d' or @code='e' or @code='f' or @code='g' or @code='h']">
				<xsl:variable name="langCodes" select="."/>
				<xsl:choose>
					<xsl:when test="../marc:subfield[@code='2']='rfc3066'">
						<!-- not stacked but could be repeated -->
						<xsl:call-template name="rfcLanguages">
							<xsl:with-param name="nodeNum">
								<xsl:value-of select="1"/>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:text></xsl:text>
							</xsl:with-param>
							<xsl:with-param name="controlField008-35-37">
								<xsl:value-of select="$controlField008-35-37"></xsl:value-of>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:when>
					<xsl:otherwise>
						<!-- iso -->
						<xsl:variable name="allLanguages">
							<xsl:copy-of select="$langCodes"></xsl:copy-of>
						</xsl:variable>
						<xsl:variable name="currentLanguage">
							<xsl:value-of select="substring($allLanguages,1,3)"></xsl:value-of>
						</xsl:variable>
						<xsl:call-template name="isoLanguage">
							<xsl:with-param name="currentLanguage">
								<xsl:value-of select="substring($allLanguages,1,3)"></xsl:value-of>
							</xsl:with-param>
							<xsl:with-param name="remainingLanguages">
								<xsl:value-of select="substring($allLanguages,4,string-length($allLanguages)-3)"></xsl:value-of>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:if test="$controlField008-35-37">
									<xsl:value-of select="$controlField008-35-37"></xsl:value-of>
								</xsl:if>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:variable name="physicalDescription">
			<!--3.2 change tmee 007/11 -->
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='a']">
				<digitalOrigin>reformatted digital</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='b']">
				<digitalOrigin>digitized microfilm</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='d']">
				<digitalOrigin>digitized other analog</digitalOrigin>
			</xsl:if>
			<xsl:variable name="controlField008-23" select="substring($controlField008,24,1)"></xsl:variable>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"></xsl:variable>
			<xsl:variable name="check008-23">
				<xsl:if test="$typeOf008='BK' or $typeOf008='MU' or $typeOf008='SE' or $typeOf008='MM'">
					<xsl:value-of select="true()"></xsl:value-of>
				</xsl:if>
			</xsl:variable>
			<xsl:variable name="check008-29">
				<xsl:if test="$typeOf008='MP' or $typeOf008='VM'">
					<xsl:value-of select="true()"></xsl:value-of>
				</xsl:if>
			</xsl:variable>
			<xsl:choose>
				<xsl:when test="($check008-23 and $controlField008-23='f') or ($check008-29 and $controlField008-29='f')">
					<form authority="marcform">braille</form>
				</xsl:when>
				<xsl:when test="($controlField008-23=' ' and ($leader6='c' or $leader6='d')) or (($typeOf008='BK' or $typeOf008='SE') and ($controlField008-23=' ' or $controlField008='r'))">
					<form authority="marcform">print</form>
				</xsl:when>
				<xsl:when test="$leader6 = 'm' or ($check008-23 and $controlField008-23='s') or ($check008-29 and $controlField008-29='s')">
					<form authority="marcform">electronic</form>
				</xsl:when>
				<xsl:when test="($check008-23 and $controlField008-23='b') or ($check008-29 and $controlField008-29='b')">
					<form authority="marcform">microfiche</form>
				</xsl:when>
				<xsl:when test="($check008-23 and $controlField008-23='a') or ($check008-29 and $controlField008-29='a')">
					<form authority="marcform">microfilm</form>
				</xsl:when>
			</xsl:choose>
			<!-- 1/04 fix -->
			<xsl:if test="marc:datafield[@tag=130]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=130]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=240]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=240]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=242]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=242]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=245]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=245]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=246]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=246]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=730]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=730]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=256]/marc:subfield[@code='a']">
				<form>
					<xsl:value-of select="."></xsl:value-of>
				</form>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=007][substring(text(),1,1)='c']">
				<xsl:choose>
					<xsl:when test="substring(text(),14,1)='a'">
						<reformattingQuality>access</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='p'">
						<reformattingQuality>preservation</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='r'">
						<reformattingQuality>replacement</reformattingQuality>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<!--3.2 change tmee 007/01 -->
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='b']">
				<form authority="smd">chip cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='c']">
				<form authority="smd">computer optical disc cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='j']">
				<form authority="smd">magnetic disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='m']">
				<form authority="smd">magneto-optical disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='o']">
				<form authority="smd">optical disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='r']">
				<form authority="smd">remote</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='a']">
				<form authority="smd">tape cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='f']">
				<form authority="smd">tape cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='h']">
				<form authority="smd">tape reel</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='a']">
				<form authority="smd">celestial globe</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='e']">
				<form authority="smd">earth moon globe</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='b']">
				<form authority="smd">planetary or lunar globe</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='c']">
				<form authority="smd">terrestrial globe</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='o'][substring(text(),2,1)='o']">
				<form authority="smd">kit</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
				<form authority="smd">atlas</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='g']">
				<form authority="smd">diagram</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
				<form authority="smd">map</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
				<form authority="smd">model</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='k']">
				<form authority="smd">profile</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='s']">
				<form authority="smd">section</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='y']">
				<form authority="smd">view</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='a']">
				<form authority="smd">aperture card</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='e']">
				<form authority="smd">microfiche</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='f']">
				<form authority="smd">microfiche cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='b']">
				<form authority="smd">microfilm cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='c']">
				<form authority="smd">microfilm cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='d']">
				<form authority="smd">microfilm reel</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='g']">
				<form authority="smd">microopaque</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='c']">
				<form authority="smd">film cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='f']">
				<form authority="smd">film cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='r']">
				<form authority="smd">film reel</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='n']">
				<form authority="smd">chart</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='c']">
				<form authority="smd">collage</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='d']">
				<form authority="smd">drawing</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='o']">
				<form authority="smd">flash card</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='e']">
				<form authority="smd">painting</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='f']">
				<form authority="smd">photomechanical print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='g']">
				<form authority="smd">photonegative</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='h']">
				<form authority="smd">photoprint</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='i']">
				<form authority="smd">picture</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='j']">
				<form authority="smd">print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='l']">
				<form authority="smd">technical drawing</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='q'][substring(text(),2,1)='q']">
				<form authority="smd">notated music</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='d']">
				<form authority="smd">filmslip</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='c']">
				<form authority="smd">filmstrip cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='o']">
				<form authority="smd">filmstrip roll</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='f']">
				<form authority="smd">other filmstrip type</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='s']">
				<form authority="smd">slide</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='t']">
				<form authority="smd">transparency</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='r'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='e']">
				<form authority="smd">cylinder</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='q']">
				<form authority="smd">roll</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='g']">
				<form authority="smd">sound cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='s']">
				<form authority="smd">sound cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='d']">
				<form authority="smd">sound disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='t']">
				<form authority="smd">sound-tape reel</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='i']">
				<form authority="smd">sound-track film</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='w']">
				<form authority="smd">wire recording</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='b']">
				<form authority="smd">combination</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='a']">
				<form authority="smd">moon</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='d']">
				<form authority="smd">tactile, with no writing system</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='b']">
				<form authority="smd">large print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='a']">
				<form authority="smd">regular print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='d']">
				<form authority="smd">text in looseleaf binder</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='c']">
				<form authority="smd">videocartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='f']">
				<form authority="smd">videocassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='d']">
				<form authority="smd">videodisc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='r']">
				<form authority="smd">videoreel</form>
			</xsl:if>
			
			<xsl:for-each select="marc:datafield[@tag=856]/marc:subfield[@code='q'][string-length(.)>1]">
				<internetMediaType>
					<xsl:value-of select="."></xsl:value-of>
				</internetMediaType>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=300]">
				<extent>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abce</xsl:with-param>
					</xsl:call-template>
				</extent>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($physicalDescription))">
			<physicalDescription>
				<xsl:copy-of select="$physicalDescription"></xsl:copy-of>
			</physicalDescription>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=520]">
			<abstract>
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</abstract>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=505]">
			<tableOfContents>
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">agrt</xsl:with-param>
				</xsl:call-template>
			</tableOfContents>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=521]">
			<targetAudience>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</targetAudience>
		</xsl:for-each>
		<xsl:if test="$typeOf008='BK' or $typeOf008='CF' or $typeOf008='MU' or $typeOf008='VM'">
			<xsl:variable name="controlField008-22" select="substring($controlField008,23,1)"></xsl:variable>
			<xsl:choose>
				<!-- 01/04 fix -->
				<xsl:when test="$controlField008-22='d'">
					<targetAudience authority="marctarget">adolescent</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='e'">
					<targetAudience authority="marctarget">adult</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='g'">
					<targetAudience authority="marctarget">general</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='b' or $controlField008-22='c' or $controlField008-22='j'">
					<targetAudience authority="marctarget">juvenile</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='a'">
					<targetAudience authority="marctarget">preschool</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='f'">
					<targetAudience authority="marctarget">specialized</targetAudience>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=245]/marc:subfield[@code='c']">
			<note type="statement of responsibility">
				<xsl:value-of select="."></xsl:value-of>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=500]">
			<note>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
				<xsl:call-template name="uri"></xsl:call-template>
			</note>
		</xsl:for-each>
		
		<!--3.2 change tmee additional note fields-->
		
		<xsl:for-each select="marc:datafield[@tag=506]">
			<note type="restrictions">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=510]">
			<note  type="citation/reference">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
			
		<xsl:for-each select="marc:datafield[@tag=511]">
			<note type="performers">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=518]">
			<note type="venue">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=530]">
			<note  type="additional physical form">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=533]">
			<note  type="reproduction">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=534]">
			<note  type="original version">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=538]">
			<note  type="system details">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=583]">
			<note type="action">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		

		
		
		
		<xsl:for-each select="marc:datafield[@tag=501 or @tag=502 or @tag=504 or @tag=507 or @tag=508 or  @tag=513 or @tag=514 or @tag=515 or @tag=516 or @tag=522 or @tag=524 or @tag=525 or @tag=526 or @tag=535 or @tag=536 or @tag=540 or @tag=541 or @tag=544 or @tag=545 or @tag=546 or @tag=547 or @tag=550 or @tag=552 or @tag=555 or @tag=556 or @tag=561 or @tag=562 or @tag=565 or @tag=567 or @tag=580 or @tag=581 or @tag=584 or @tag=585 or @tag=586]">
			<note>
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=034][marc:subfield[@code='d' or @code='e' or @code='f' or @code='g']]">
			<subject>
				<cartographics>
					<coordinates>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">defg</xsl:with-param>
						</xsl:call-template>
					</coordinates>
				</cartographics>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=043]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
					<geographicCode>
						<xsl:attribute name="authority">
							<xsl:if test="@code='a'">
								<xsl:text>marcgac</xsl:text>
							</xsl:if>
							<xsl:if test="@code='b'">
								<xsl:value-of select="following-sibling::marc:subfield[@code=2]"></xsl:value-of>
							</xsl:if>
							<xsl:if test="@code='c'">
								<xsl:text>iso3166</xsl:text>
							</xsl:if>
						</xsl:attribute>
						<xsl:value-of select="self::marc:subfield"></xsl:value-of>
					</geographicCode>
				</xsl:for-each>
			</subject>
		</xsl:for-each>
		<!-- tmee 2006/11/27 -->
		<xsl:for-each select="marc:datafield[@tag=255]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
				<cartographics>
					<xsl:if test="@code='a'">
						<scale>
							<xsl:value-of select="."></xsl:value-of>
						</scale>
					</xsl:if>
					<xsl:if test="@code='b'">
						<projection>
							<xsl:value-of select="."></xsl:value-of>
						</projection>
					</xsl:if>
					<xsl:if test="@code='c'">
						<coordinates>
							<xsl:value-of select="."></xsl:value-of>
						</coordinates>
					</xsl:if>
				</cartographics>
				</xsl:for-each>
			</subject>
		</xsl:for-each>
				
		<xsl:apply-templates select="marc:datafield[653 >= @tag and @tag >= 600]"></xsl:apply-templates>
		<xsl:apply-templates select="marc:datafield[@tag=656]"></xsl:apply-templates>
		<xsl:for-each select="marc:datafield[@tag=752]">
			<subject>
				<hierarchicalGeographic>
					<xsl:for-each select="marc:subfield[@code='a']">
						<country>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</country>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<state>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</state>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='c']">
						<county>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</county>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='d']">
						<city>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</city>
					</xsl:for-each>
				</hierarchicalGeographic>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=045][marc:subfield[@code='b']]">
			<subject>
				<xsl:choose>
					<xsl:when test="@ind1=2">
						<temporal encoding="iso8601" point="start">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][1]"></xsl:value-of>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
						<temporal encoding="iso8601" point="end">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][2]"></xsl:value-of>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
					</xsl:when>
					<xsl:otherwise>
						<xsl:for-each select="marc:subfield[@code='b']">
							<temporal encoding="iso8601">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."></xsl:with-param>
								</xsl:call-template>
							</temporal>
						</xsl:for-each>
					</xsl:otherwise>
				</xsl:choose>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=050]">
			<xsl:for-each select="marc:subfield[@code='b']">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"></xsl:value-of>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="preceding-sibling::marc:subfield[@code='a'][1]"></xsl:value-of>
					<xsl:text> </xsl:text>
					<xsl:value-of select="text()"></xsl:value-of>
				</classification>
			</xsl:for-each>
			<xsl:for-each select="marc:subfield[@code='a'][not(following-sibling::marc:subfield[@code='b'])]">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"></xsl:value-of>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="text()"></xsl:value-of>
				</classification>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=082]">
			<classification authority="ddc">
				<xsl:if test="marc:subfield[@code='2']">
					<xsl:attribute name="edition">
						<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
					</xsl:attribute>
				</xsl:if>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=080]">
			<classification authority="udc">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abx</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=060]">
			<classification authority="nlm">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=0]">
			<classification authority="sudocs">
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=1]">
			<classification authority="candoc">
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
				</xsl:attribute>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=084]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=440]">
			<relatedItem type="series">
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">av</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<titleInfo>
					<title>
						<xsl:value-of select="$titleChop" />
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<titleInfo type="nfi">
					<xsl:choose>
						<xsl:when test="@ind2>0">
							<nonSort>
								<xsl:value-of select="substring($titleChop,1,@ind2)"/>
							</nonSort>
							<title>
								<xsl:value-of select="substring($titleChop,@ind2+1)"/>
							</title>
							<xsl:call-template name="part"/>
						</xsl:when>
						<xsl:otherwise>
							<title>
								<xsl:value-of select="$titleChop" />
							</title>
						</xsl:otherwise>
					</xsl:choose>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=490][@ind1=0]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=510]">
			<relatedItem type="isReferencedBy">
				<note>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcx3</xsl:with-param>
					</xsl:call-template>
				</note>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=534]">
			<relatedItem type="original">
				<xsl:call-template name="relatedTitle"></xsl:call-template>
				<xsl:call-template name="relatedName"></xsl:call-template>
				<xsl:if test="marc:subfield[@code='b' or @code='c']">
					<originInfo>
						<xsl:for-each select="marc:subfield[@code='c']">
							<publisher>
								<xsl:value-of select="."></xsl:value-of>
							</publisher>
						</xsl:for-each>
						<xsl:for-each select="marc:subfield[@code='b']">
							<edition>
								<xsl:value-of select="."></xsl:value-of>
							</edition>
						</xsl:for-each>
					</originInfo>
				</xsl:if>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
				<xsl:for-each select="marc:subfield[@code='z']">
					<identifier type="isbn">
						<xsl:value-of select="."></xsl:value-of>
					</identifier>
				</xsl:for-each>
				<xsl:call-template name="relatedNote"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=700][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aq</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">g</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"></xsl:call-template>
					<xsl:call-template name="nameDate"></xsl:call-template>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=710][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<xsl:variable name="tempNamePart">
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</xsl:variable>
					<xsl:if test="normalize-space($tempNamePart)">
						<namePart>
							<xsl:value-of select="$tempNamePart"></xsl:value-of>
						</namePart>
					</xsl:if>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=711][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=730][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=740][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<titleInfo>
					<title>
						<xsl:value-of select="$titleChop" />
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<titleInfo type="nfi">
					<xsl:choose>
						<xsl:when test="@ind1>0">
							<nonSort>
								<xsl:value-of select="substring($titleChop,1,@ind1)"/>
							</nonSort>
							<title>
								<xsl:value-of select="substring($titleChop,@ind1+1)"/>
							</title>
						</xsl:when>
						<xsl:otherwise>
							<title>
								<xsl:value-of select="$titleChop" />
							</title>
						</xsl:otherwise>
					</xsl:choose>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<xsl:call-template name="relatedForm"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=760]|marc:datafield[@tag=762]">
			<relatedItem type="series">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=765]|marc:datafield[@tag=767]|marc:datafield[@tag=777]|marc:datafield[@tag=787]">
			<relatedItem>
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=775]">
			<relatedItem type="otherVersion">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=770]|marc:datafield[@tag=774]">
			<relatedItem type="constituent">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=772]|marc:datafield[@tag=773]">
			<relatedItem type="host">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=776]">
			<relatedItem type="otherFormat">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=780]">
			<relatedItem type="preceding">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=785]">
			<relatedItem type="succeeding">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=786]">
			<relatedItem type="original">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=800]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">aq</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="beforeCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"></xsl:call-template>
					<xsl:call-template name="nameDate"></xsl:call-template>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=810]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=811]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='830']">
			<relatedItem type="series">
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<titleInfo>
					<title>
						<xsl:value-of select="$titleChop" />
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<titleInfo type="nfi">
					<xsl:choose>
						<xsl:when test="@ind2>0">
							<nonSort>
								<xsl:value-of select="substring($titleChop,1,@ind2)"/>
							</nonSort>
							<title>
								<xsl:value-of select="substring($titleChop,@ind2+1)"/>
							</title>
						</xsl:when>
						<xsl:otherwise>
							<title>
								<xsl:value-of select="$titleChop" />
							</title>
						</xsl:otherwise>
					</xsl:choose>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][@ind2='2']/marc:subfield[@code='q']">
			<relatedItem>
				<internetMediaType>
					<xsl:value-of select="."/>
				</internetMediaType>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='020']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isbn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isbn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='0']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isrc</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isrc">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='2']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">ismn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="ismn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='4']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">sici</xsl:with-param>
			</xsl:call-template>
			<identifier type="sici">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='022']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">issn</xsl:with-param>
			</xsl:call-template>
			<identifier type="issn">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='010']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">lccn</xsl:with-param>
			</xsl:call-template>
			<identifier type="lccn">
				<xsl:value-of select="normalize-space(marc:subfield[@code='a'])"/>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='028']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when test="@ind1='0'">issue number</xsl:when>
						<xsl:when test="@ind1='1'">matrix number</xsl:when>
						<xsl:when test="@ind1='2'">music plate</xsl:when>
						<xsl:when test="@ind1='3'">music publisher</xsl:when>
						<xsl:when test="@ind1='4'">videorecording identifier</xsl:when>
					</xsl:choose>
				</xsl:attribute>
				<!--<xsl:call-template name="isInvalid"/>--> <!-- no $z in 028 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">
						<xsl:choose>
							<xsl:when test="@ind1='0'">ba</xsl:when>
							<xsl:otherwise>ab</xsl:otherwise>
						</xsl:choose>
					</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='037']">
			<identifier type="stock number">
				<!--<xsl:call-template name="isInvalid"/>--> <!-- no $z in 037 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][marc:subfield[@code='u']]">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when test="starts-with(marc:subfield[@code='u'],'urn:doi') or starts-with(marc:subfield[@code='u'],'doi')">doi</xsl:when>
						<xsl:when test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov')">hdl</xsl:when>
						<xsl:otherwise>uri</xsl:otherwise>
					</xsl:choose>
				</xsl:attribute>
				<xsl:choose>
					<xsl:when test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov') ">
						<xsl:value-of select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"></xsl:value-of>
					</xsl:when>
					<xsl:otherwise>
						<xsl:value-of select="marc:subfield[@code='u']"></xsl:value-of>
					</xsl:otherwise>
				</xsl:choose>
			</identifier>
			<xsl:if test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl')">
				<identifier type="hdl">
					<xsl:if test="marc:subfield[@code='y' or @code='3' or @code='z']">
						<xsl:attribute name="displayLabel">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">y3z</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"></xsl:value-of>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=024][@ind1=1]">
			<identifier type="upc">
				<xsl:call-template name="isInvalid"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</identifier>
		</xsl:for-each>
		<!-- 1/04 fix added $y -->
		<xsl:for-each select="marc:datafield[@tag=856][marc:subfield[@code='u']]">
			<location>
				<url>
					<xsl:if test="marc:subfield[@code='y' or @code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">y3</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:if test="marc:subfield[@code='z' ]">
						<xsl:attribute name="note">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">z</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="marc:subfield[@code='u']"></xsl:value-of>

				</url>
			</location>
		</xsl:for-each>
			
			<!-- 3.2 change tmee 856z  -->

		
		<xsl:for-each select="marc:datafield[@tag=852]">
			<location>
				<physicalLocation>
					<xsl:call-template name="displayLabel"></xsl:call-template>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abje</xsl:with-param>
					</xsl:call-template>
				</physicalLocation>
			</location>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=506]">
			<accessCondition type="restrictionOnAccess">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcd35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=540]">
			<accessCondition type="useAndReproduction">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcde35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>
		<recordInfo>
			<xsl:for-each select="marc:datafield[@tag=040]">
				<recordContentSource authority="marcorg">
					<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
				</recordContentSource>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=008]">
				<recordCreationDate encoding="marc">
					<xsl:value-of select="substring(.,1,6)"></xsl:value-of>
				</recordCreationDate>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=005]">
				<recordChangeDate encoding="iso8601">
					<xsl:value-of select="."></xsl:value-of>
				</recordChangeDate>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=001]">
				<recordIdentifier>
					<xsl:if test="../marc:controlfield[@tag=003]">
						<xsl:attribute name="source">
							<xsl:value-of select="../marc:controlfield[@tag=003]"></xsl:value-of>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="."></xsl:value-of>
				</recordIdentifier>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=040]/marc:subfield[@code='b']">
				<languageOfCataloging>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="."></xsl:value-of>
					</languageTerm>
				</languageOfCataloging>
			</xsl:for-each>
		</recordInfo>
	</xsl:template>
	<xsl:template name="displayForm">
		<xsl:for-each select="marc:subfield[@code='c']">
			<displayForm>
				<xsl:value-of select="."></xsl:value-of>
			</displayForm>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="affiliation">
		<xsl:for-each select="marc:subfield[@code='u']">
			<affiliation>
				<xsl:value-of select="."></xsl:value-of>
			</affiliation>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="uri">
		<xsl:for-each select="marc:subfield[@code='u']">
			<xsl:attribute name="xlink:href">
				<xsl:value-of select="."></xsl:value-of>
			</xsl:attribute>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='0']">
			<xsl:choose>
				<xsl:when test="contains(text(), ')')">
					<xsl:attribute name="xlink:href">
						<xsl:value-of select="substring-after(text(), ')')"></xsl:value-of>
					</xsl:attribute>
				</xsl:when>
				<xsl:otherwise>
					<xsl:attribute name="xlink:href">
						<xsl:value-of select="."></xsl:value-of>
					</xsl:attribute>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="role">
		<xsl:for-each select="marc:subfield[@code='e']">
			<role>
				<roleTerm type="text">
					<xsl:value-of select="."></xsl:value-of>
				</roleTerm>
			</role>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='4']">
			<role>
				<roleTerm authority="marcrelator" type="code">
					<xsl:value-of select="."></xsl:value-of>
				</roleTerm>
			</role>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="part">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">n</xsl:with-param>
				<xsl:with-param name="anyCodes">n</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partNumber"></xsl:with-param>
				</xsl:call-template>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partName"></xsl:with-param>
				</xsl:call-template>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPart">
		<xsl:if test="@tag=773">
			<xsl:for-each select="marc:subfield[@code='g']">
				<part>
					<text>
						<xsl:value-of select="."></xsl:value-of>
					</text>
				</part>
			</xsl:for-each>
			<xsl:for-each select="marc:subfield[@code='q']">
				<part>
					<xsl:call-template name="parsePart"></xsl:call-template>
				</part>
			</xsl:for-each>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPartNumName">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">g</xsl:with-param>
				<xsl:with-param name="anyCodes">g</xsl:with-param>
				<xsl:with-param name="afterCodes">pst</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:value-of select="$partNumber"></xsl:value-of>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:value-of select="$partName"></xsl:value-of>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedName">
		<xsl:for-each select="marc:subfield[@code='a']">
			<name>
				<namePart>
					<xsl:value-of select="."></xsl:value-of>
				</namePart>
			</name>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedForm">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<form>
					<xsl:value-of select="."></xsl:value-of>
				</form>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedExtent">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<extent>
					<xsl:value-of select="."></xsl:value-of>
				</extent>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedNote">
		<xsl:for-each select="marc:subfield[@code='n']">
			<note>
				<xsl:value-of select="."></xsl:value-of>
			</note>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedSubject">
		<xsl:for-each select="marc:subfield[@code='j']">
			<subject>
				<temporal encoding="iso8601">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."></xsl:with-param>
					</xsl:call-template>
				</temporal>
			</subject>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierISSN">
		<xsl:for-each select="marc:subfield[@code='x']">
			<identifier type="issn">
				<xsl:value-of select="."></xsl:value-of>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierLocal">
		<xsl:for-each select="marc:subfield[@code='w']">
			<identifier type="local">
				<xsl:value-of select="."></xsl:value-of>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifier">
		<xsl:for-each select="marc:subfield[@code='o']">
			<identifier>
				<xsl:value-of select="."></xsl:value-of>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedItem76X-78X">
		<xsl:call-template name="displayLabel"></xsl:call-template>
		<xsl:call-template name="relatedTitle76X-78X"></xsl:call-template>
		<xsl:call-template name="relatedName"></xsl:call-template>
		<xsl:call-template name="relatedOriginInfo"></xsl:call-template>
		<xsl:call-template name="relatedLanguage"></xsl:call-template>
		<xsl:call-template name="relatedExtent"></xsl:call-template>
		<xsl:call-template name="relatedNote"></xsl:call-template>
		<xsl:call-template name="relatedSubject"></xsl:call-template>
		<xsl:call-template name="relatedIdentifier"></xsl:call-template>
		<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
		<xsl:call-template name="relatedIdentifierLocal"></xsl:call-template>
		<xsl:call-template name="relatedPart"></xsl:call-template>
	</xsl:template>
	<xsl:template name="subjectGeographicZ">
		<geographic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</geographic>
	</xsl:template>
	<xsl:template name="subjectTemporalY">
		<temporal>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</temporal>
	</xsl:template>
	<xsl:template name="subjectTopic">
		<topic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</topic>
	</xsl:template>	
	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template name="subjectGenre">
		<genre>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</genre>
	</xsl:template>
	
	<xsl:template name="nameABCDN">
		<xsl:for-each select="marc:subfield[@code='a']">
			<namePart>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."></xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='b']">
			<namePart>
				<xsl:value-of select="."></xsl:value-of>
			</namePart>
		</xsl:for-each>
		<xsl:if test="marc:subfield[@code='c'] or marc:subfield[@code='d'] or marc:subfield[@code='n']">
			<namePart>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">cdn</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="nameABCDQ">
		<namePart>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">aq</xsl:with-param>
					</xsl:call-template>
				</xsl:with-param>
				<xsl:with-param name="punctuation">
					<xsl:text>:,;/ </xsl:text>
				</xsl:with-param>
			</xsl:call-template>
		</namePart>
		<xsl:call-template name="termsOfAddress"></xsl:call-template>
		<xsl:call-template name="nameDate"></xsl:call-template>
	</xsl:template>
	<xsl:template name="nameACDEQ">
		<namePart>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">acdeq</xsl:with-param>
			</xsl:call-template>
		</namePart>
	</xsl:template>
	<xsl:template name="constituentOrRelatedType">
		<xsl:if test="@ind2=2">
			<xsl:attribute name="type">constituent</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedTitle">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedTitle76X-78X">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='p']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='s']">
			<titleInfo type="uniform">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedOriginInfo">
		<xsl:if test="marc:subfield[@code='b' or @code='d'] or marc:subfield[@code='f']">
			<originInfo>
				<xsl:if test="@tag=775">
					<xsl:for-each select="marc:subfield[@code='f']">
						<place>
							<placeTerm>
								<xsl:attribute name="type">code</xsl:attribute>
								<xsl:attribute name="authority">marcgac</xsl:attribute>
								<xsl:value-of select="."></xsl:value-of>
							</placeTerm>
						</place>
					</xsl:for-each>
				</xsl:if>
				<xsl:for-each select="marc:subfield[@code='d']">
					<publisher>
						<xsl:value-of select="."></xsl:value-of>
					</publisher>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<edition>
						<xsl:value-of select="."></xsl:value-of>
					</edition>
				</xsl:for-each>
			</originInfo>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedLanguage">
		<xsl:for-each select="marc:subfield[@code='e']">
			<xsl:call-template name="getLanguage">
				<xsl:with-param name="langString">
					<xsl:value-of select="."></xsl:value-of>
				</xsl:with-param>
			</xsl:call-template>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="nameDate">
		<xsl:for-each select="marc:subfield[@code='d']">
			<namePart type="date">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."></xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="subjectAuthority">
		<xsl:if test="@ind2!=4">
			<xsl:if test="@ind2!=' '">
				<xsl:if test="@ind2!=8">
					<xsl:if test="@ind2!=9">
						<xsl:attribute name="authority">
							<xsl:choose>
								<xsl:when test="@ind2=0">lcsh</xsl:when>
								<xsl:when test="@ind2=1">lcshac</xsl:when>
								<xsl:when test="@ind2=2">mesh</xsl:when>
								<!-- 1/04 fix -->
								<xsl:when test="@ind2=3">nal</xsl:when>
								<xsl:when test="@ind2=5">csh</xsl:when>
								<xsl:when test="@ind2=6">rvm</xsl:when>
								<xsl:when test="@ind2=7">
									<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
								</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
				</xsl:if>
			</xsl:if>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subjectAnyOrder">
		<xsl:for-each select="marc:subfield[@code='v' or @code='x' or @code='y' or @code='z']">
			<xsl:choose>
				<xsl:when test="@code='v'">
					<xsl:call-template name="subjectGenre"></xsl:call-template>
				</xsl:when>
				<xsl:when test="@code='x'">
					<xsl:call-template name="subjectTopic"></xsl:call-template>
				</xsl:when>
				<xsl:when test="@code='y'">
					<xsl:call-template name="subjectTemporalY"></xsl:call-template>
				</xsl:when>
				<xsl:when test="@code='z'">
					<xsl:call-template name="subjectGeographicZ"></xsl:call-template>
				</xsl:when>
			</xsl:choose>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="specialSubfieldSelect">
		<xsl:param name="anyCodes"></xsl:param>
		<xsl:param name="axis"></xsl:param>
		<xsl:param name="beforeCodes"></xsl:param>
		<xsl:param name="afterCodes"></xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($anyCodes, @code)      or (contains($beforeCodes,@code) and following-sibling::marc:subfield[@code=$axis])      or (contains($afterCodes,@code) and preceding-sibling::marc:subfield[@code=$axis])">
					<xsl:value-of select="text()"></xsl:value-of>
					<xsl:text> </xsl:text>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
	</xsl:template>
	
	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template match="marc:datafield[@tag=600]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<name type="personal">
				<xsl:call-template name="uri" />
				<xsl:call-template name="termsOfAddress"></xsl:call-template>
				<namePart>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">aq</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:call-template name="nameDate"></xsl:call-template>
				<xsl:call-template name="affiliation"></xsl:call-template>
				<xsl:call-template name="role"></xsl:call-template>
			</name>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=610]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<name type="corporate">
				<xsl:call-template name="uri" />
				<xsl:for-each select="marc:subfield[@code='a']">
					<namePart>
						<xsl:value-of select="."></xsl:value-of>
					</namePart>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<namePart>
						<xsl:value-of select="."></xsl:value-of>
					</namePart>
				</xsl:for-each>
				<xsl:if test="marc:subfield[@code='c' or @code='d' or @code='n' or @code='p']">
					<namePart>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">cdnp</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</xsl:if>
				<xsl:call-template name="role"></xsl:call-template>
			</name>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=611]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<name type="conference">
				<xsl:call-template name="uri" />
				<namePart>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcdeqnp</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:for-each select="marc:subfield[@code='4']">
					<role>
						<roleTerm authority="marcrelator" type="code">
							<xsl:value-of select="."></xsl:value-of>
						</roleTerm>
					</role>
				</xsl:for-each>
			</name>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=630]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<xsl:variable name="titleChop">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">adfhklor</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:variable>
			<titleInfo>
				<title>
					<xsl:value-of select="$titleChop" />
				</title>
				<xsl:call-template name="part"></xsl:call-template>
			</titleInfo>
			<titleInfo type="nfi">
				<xsl:choose>
					<xsl:when test="@ind1>0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind1)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind1+1)"/>
						</title>
						<xsl:call-template name="part"/>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop" />
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:call-template name="part"></xsl:call-template>
			</titleInfo>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=650]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<topic>
				<xsl:call-template name="uri" />
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abcd</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</topic>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=651]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<xsl:for-each select="marc:subfield[@code='a']">
				<geographic>
					<xsl:call-template name="uri" />
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."></xsl:with-param>
					</xsl:call-template>
				</geographic>
			</xsl:for-each>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=653]">
		<subject>
			<xsl:for-each select="marc:subfield[@code='a']">
				<topic>
					<xsl:call-template name="uri" />
					<xsl:value-of select="."></xsl:value-of>
				</topic>
			</xsl:for-each>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=656]">
		<subject>
			<xsl:if test="marc:subfield[@code=2]">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code=2]"></xsl:value-of>
				</xsl:attribute>
			</xsl:if>
			<occupation>
				<xsl:call-template name="uri" />
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
					</xsl:with-param>
				</xsl:call-template>
			</occupation>
		</subject>
	</xsl:template>
	<xsl:template name="termsOfAddress">
		<xsl:if test="marc:subfield[@code='b' or @code='c']">
			<namePart type="termsOfAddress">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">bc</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="displayLabel">
		<xsl:if test="marc:subfield[@code='i']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='i']"></xsl:value-of>
			</xsl:attribute>
		</xsl:if>
		<xsl:if test="marc:subfield[@code='3']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='3']"></xsl:value-of>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="isInvalid">
		<xsl:param name="type"/>
		<xsl:if test="marc:subfield[@code='z'] or marc:subfield[@code='y']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:value-of select="$type"/>
				</xsl:attribute>
				<xsl:attribute name="invalid">
					<xsl:text>yes</xsl:text>
				</xsl:attribute>
				<xsl:if test="marc:subfield[@code='z']">
					<xsl:value-of select="marc:subfield[@code='z']"/>
				</xsl:if>
				<xsl:if test="marc:subfield[@code='y']">
					<xsl:value-of select="marc:subfield[@code='y']"/>
				</xsl:if>
			</identifier>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subtitle">
		<xsl:if test="marc:subfield[@code='b']">
			<subTitle>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='b']"/>
						<!--<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">b</xsl:with-param>									
						</xsl:call-template>-->
					</xsl:with-param>
				</xsl:call-template>
			</subTitle>
		</xsl:if>
	</xsl:template>
	<xsl:template name="script">
		<xsl:param name="scriptCode"></xsl:param>
		<xsl:attribute name="script">
			<xsl:choose>
				<xsl:when test="$scriptCode='(3'">Arabic</xsl:when>
				<xsl:when test="$scriptCode='(B'">Latin</xsl:when>
				<xsl:when test="$scriptCode='$1'">Chinese, Japanese, Korean</xsl:when>
				<xsl:when test="$scriptCode='(N'">Cyrillic</xsl:when>
				<xsl:when test="$scriptCode='(2'">Hebrew</xsl:when>
				<xsl:when test="$scriptCode='(S'">Greek</xsl:when>
			</xsl:choose>
		</xsl:attribute>
	</xsl:template>
	<xsl:template name="parsePart">
		<!-- assumes 773$q= 1:2:3<4
		     with up to 3 levels and one optional start page
		-->
		<xsl:variable name="level1">
			<xsl:choose>
				<xsl:when test="contains(text(),':')">
					<!-- 1:2 -->
					<xsl:value-of select="substring-before(text(),':')"></xsl:value-of>
				</xsl:when>
				<xsl:when test="not(contains(text(),':'))">
					<!-- 1 or 1<3 -->
					<xsl:if test="contains(text(),'&lt;')">
						<!-- 1<3 -->
						<xsl:value-of select="substring-before(text(),'&lt;')"></xsl:value-of>
					</xsl:if>
					<xsl:if test="not(contains(text(),'&lt;'))">
						<!-- 1 -->
						<xsl:value-of select="text()"></xsl:value-of>
					</xsl:if>
				</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici2">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after(text(),$level1),':')">
					<xsl:value-of select="substring(substring-after(text(),$level1),2)"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after(text(),$level1)"></xsl:value-of>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level2">
			<xsl:choose>
				<xsl:when test="contains($sici2,':')">
					<!--  2:3<4  -->
					<xsl:value-of select="substring-before($sici2,':')"></xsl:value-of>
				</xsl:when>
				<xsl:when test="contains($sici2,'&lt;')">
					<!-- 1: 2<4 -->
					<xsl:value-of select="substring-before($sici2,'&lt;')"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici2"></xsl:value-of>
					<!-- 1:2 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici3">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after($sici2,$level2),':')">
					<xsl:value-of select="substring(substring-after($sici2,$level2),2)"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after($sici2,$level2)"></xsl:value-of>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level3">
			<xsl:choose>
				<xsl:when test="contains($sici3,'&lt;')">
					<!-- 2<4 -->
					<xsl:value-of select="substring-before($sici3,'&lt;')"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici3"></xsl:value-of>
					<!-- 3 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="page">
			<xsl:if test="contains(text(),'&lt;')">
				<xsl:value-of select="substring-after(text(),'&lt;')"></xsl:value-of>
			</xsl:if>
		</xsl:variable>
		<xsl:if test="$level1">
			<detail level="1">
				<number>
					<xsl:value-of select="$level1"></xsl:value-of>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level2">
			<detail level="2">
				<number>
					<xsl:value-of select="$level2"></xsl:value-of>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level3">
			<detail level="3">
				<number>
					<xsl:value-of select="$level3"></xsl:value-of>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$page">
			<extent unit="page">
				<start>
					<xsl:value-of select="$page"></xsl:value-of>
				</start>
			</extent>
		</xsl:if>
	</xsl:template>
	<xsl:template name="getLanguage">
		<xsl:param name="langString"></xsl:param>
		<xsl:param name="controlField008-35-37"></xsl:param>
		<xsl:variable name="length" select="string-length($langString)"></xsl:variable>
		<xsl:choose>
			<xsl:when test="$length=0"></xsl:when>
			<xsl:when test="$controlField008-35-37=substring($langString,1,3)">
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"></xsl:with-param>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"></xsl:with-param>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<language>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="substring($langString,1,3)"></xsl:value-of>
					</languageTerm>
				</language>
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"></xsl:with-param>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"></xsl:with-param>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="isoLanguage">
		<xsl:param name="currentLanguage"></xsl:param>
		<xsl:param name="usedLanguages"></xsl:param>
		<xsl:param name="remainingLanguages"></xsl:param>
		<xsl:choose>
			<xsl:when test="string-length($currentLanguage)=0"></xsl:when>
			<xsl:when test="not(contains($usedLanguages, $currentLanguage))">
				<language>
					<xsl:if test="@code!='a'">
						<xsl:attribute name="objectPart">
							<xsl:choose>
								<xsl:when test="@code='b'">summary or subtitle</xsl:when>
								<xsl:when test="@code='d'">sung or spoken text</xsl:when>
								<xsl:when test="@code='e'">libretto</xsl:when>
								<xsl:when test="@code='f'">table of contents</xsl:when>
								<xsl:when test="@code='g'">accompanying material</xsl:when>
								<xsl:when test="@code='h'">translation</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="$currentLanguage"></xsl:value-of>
					</languageTerm>
				</language>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of select="substring($remainingLanguages,4,string-length($remainingLanguages))"></xsl:value-of>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of select="substring($remainingLanguages,4,string-length($remainingLanguages))"></xsl:value-of>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="chopBrackets">
		<xsl:param name="chopString"></xsl:param>
		<xsl:variable name="string">
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="$chopString"></xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="substring($string, 1,1)='['">
			<xsl:value-of select="substring($string,2, string-length($string)-2)"></xsl:value-of>
		</xsl:if>
		<xsl:if test="substring($string, 1,1)!='['">
			<xsl:value-of select="$string"></xsl:value-of>
		</xsl:if>
	</xsl:template>
	<xsl:template name="rfcLanguages">
		<xsl:param name="nodeNum"></xsl:param>
		<xsl:param name="usedLanguages"></xsl:param>
		<xsl:param name="controlField008-35-37"></xsl:param>
		<xsl:variable name="currentLanguage" select="."></xsl:variable>
		<xsl:choose>
			<xsl:when test="not($currentLanguage)"></xsl:when>
			<xsl:when test="$currentLanguage!=$controlField008-35-37 and $currentLanguage!='rfc3066'">
				<xsl:if test="not(contains($usedLanguages,$currentLanguage))">
					<language>
						<xsl:if test="@code!='a'">
							<xsl:attribute name="objectPart">
								<xsl:choose>
									<xsl:when test="@code='b'">summary or subtitle</xsl:when>
									<xsl:when test="@code='d'">sung or spoken text</xsl:when>
									<xsl:when test="@code='e'">libretto</xsl:when>
									<xsl:when test="@code='f'">table of contents</xsl:when>
									<xsl:when test="@code='g'">accompanying material</xsl:when>
									<xsl:when test="@code='h'">translation</xsl:when>
								</xsl:choose>
							</xsl:attribute>
						</xsl:if>
						<languageTerm authority="rfc3066" type="code">
							<xsl:value-of select="$currentLanguage"/>
						</languageTerm>
					</language>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="datafield">
		<xsl:param name="tag"/>
		<xsl:param name="ind1"><xsl:text> </xsl:text></xsl:param>
		<xsl:param name="ind2"><xsl:text> </xsl:text></xsl:param>
		<xsl:param name="subfields"/>
		<xsl:element name="marc:datafield">
			<xsl:attribute name="tag">
				<xsl:value-of select="$tag"/>
			</xsl:attribute>
			<xsl:attribute name="ind1">
				<xsl:value-of select="$ind1"/>
			</xsl:attribute>
			<xsl:attribute name="ind2">
				<xsl:value-of select="$ind2"/>
			</xsl:attribute>
			<xsl:copy-of select="$subfields"/>
		</xsl:element>
	</xsl:template>

	<xsl:template name="subfieldSelect">
		<xsl:param name="codes"/>
		<xsl:param name="delimeter"><xsl:text> </xsl:text></xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($codes, @code)">
					<xsl:value-of select="text()"/><xsl:value-of select="$delimeter"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
	</xsl:template>

	<xsl:template name="buildSpaces">
		<xsl:param name="spaces"/>
		<xsl:param name="char"><xsl:text> </xsl:text></xsl:param>
		<xsl:if test="$spaces>0">
			<xsl:value-of select="$char"/>
			<xsl:call-template name="buildSpaces">
				<xsl:with-param name="spaces" select="$spaces - 1"/>
				<xsl:with-param name="char" select="$char"/>
			</xsl:call-template>
		</xsl:if>
	</xsl:template>

	<xsl:template name="chopPunctuation">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation"><xsl:text>.:,;/ </xsl:text></xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise><xsl:value-of select="$chopString"/></xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationFront">
		<xsl:param name="chopString"/>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains('.:,;/[ ', substring($chopString,1,1))">
				<xsl:call-template name="chopPunctuationFront">
					<xsl:with-param name="chopString" select="substring($chopString,2,$length - 1)"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise><xsl:value-of select="$chopString"/></xsl:otherwise>
		</xsl:choose>
	</xsl:template>
</xsl:stylesheet>$$ WHERE name = 'mods32';


-- 954.data.MODS33-xsl.sql
UPDATE config.xml_transform SET xslt=$$<xsl:stylesheet xmlns="http://www.loc.gov/mods/v3" xmlns:marc="http://www.loc.gov/MARC21/slim"
	xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
	exclude-result-prefixes="xlink marc" version="1.0">
	<xsl:output encoding="UTF-8" indent="yes" method="xml"/>

	<xsl:variable name="ascii">
		<xsl:text> !"#$%&amp;'()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~</xsl:text>
	</xsl:variable>

	<xsl:variable name="latin1">
		<xsl:text> ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ</xsl:text>
	</xsl:variable>
	<!-- Characters that usually don't need to be escaped -->
	<xsl:variable name="safe">
		<xsl:text>!'()*-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~</xsl:text>
	</xsl:variable>

	<xsl:variable name="hex">0123456789ABCDEF</xsl:variable>

    <!-- Evergreen specific: revert Revision 1.23, so we can have those authority xlink attributes back. -->

	<!--MARC21slim2MODS3-3.xsl
Revision 1.27 - Mapped 648 to <subject> 2009/03/13 tmee
Revision 1.26 - Added subfield $s mapping for 130/240/730  2008/10/16 tmee
Revision 1.25 - Mapped 040e to <descriptiveStandard> and Leader/18 to <descriptive standard>aacr2  2008/09/18 tmee
Revision 1.24 - Mapped 852 subfields $h, $i, $j, $k, $l, $m, $t to <shelfLocation> and 852 subfield $u to <physicalLocation> with @xlink 2008/09/17 tmee
Revision 1.23 - Commented out xlink/uri for subfield 0 for 130/240/730, 100/700, 110/710, 111/711 as these are currently unactionable  2008/09/17  tmee
Revision 1.22 - Mapped 022 subfield $l to type "issn-l" subfield $m to output identifier element with corresponding @type and @invalid eq 'yes'2008/09/17  tmee
Revision 1.21 - Mapped 856 ind2=1 or ind2=2 to <relatedItem><location><url>  2008/07/03  tmee
Revision 1.20 - Added genre w/@auth="contents of 2" and type= "musical composition"  2008/07/01  tmee
Revision 1.19 - Added genre offprint for 008/24+ BK code 2  2008/07/01  tmee
Revision 1.18 - Added xlink/uri for subfield 0 for 130/240/730, 100/700, 110/710, 111/711  2008/06/26  tmee
Revision 1.17 - Added mapping of 662 2008/05/14 tmee	
Revision 1.16 - Changed @authority from "marc" to "marcgt" for 007 and 008 codes mapped to a term in <genre> 2007/07/10  tmee
Revision 1.15 - For field 630, moved call to part template outside title element  2007/07/10  tmee
Revision 1.14 - Fixed template isValid and fields 010, 020, 022, 024, 028, and 037 to output additional identifier elements with corresponding @type and @invalid eq 'yes' when subfields z or y (in the case of 022) exist in the MARCXML ::: 2007/01/04 17:35:20 cred
Revision 1.13 - Changed order of output under cartographics to reflect schema  2006/11/28  tmee
Revision 1.12 - Updated to reflect MODS 3.2 Mapping  2006/10/11  tmee
Revision 1.11 - The attribute objectPart moved from <languageTerm> to <language>  2006/04/08  jrad
Revision 1.10 - MODS 3.1 revisions to language and classification elements  (plus ability to find marc:collection embedded in wrapper elements such as SRU zs: wrappers)  2006/02/06  ggar
Revision 1.9 - Subfield $y was added to field 242 2004/09/02 10:57 jrad
Revision 1.8 - Subject chopPunctuation expanded and attribute fixes 2004/08/12 jrad
Revision 1.7 - 2004/03/25 08:29 jrad
Revision 1.6 - Various validation fixes 2004/02/20 ntra
Revision 1.5 - MODS2 to MODS3 updates, language unstacking and de-duping, chopPunctuation expanded  2003/10/02 16:18:58  ntra
Revision 1.3 - Additional Changes not related to MODS Version 2.0 by ntra
Revision 1.2 - Added Log Comment  2003/03/24 19:37:42  ckeith
-->
	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="//marc:collection">
				<modsCollection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
					xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:collection/marc:record">
						<mods version="3.3">
							<xsl:call-template name="marcRecord"/>
						</mods>
					</xsl:for-each>
				</modsCollection>
			</xsl:when>
			<xsl:otherwise>
				<mods xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="3.3"
					xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:record">
						<xsl:call-template name="marcRecord"/>
					</xsl:for-each>
				</mods>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="marcRecord">
		<xsl:variable name="leader" select="marc:leader"/>
		<xsl:variable name="leader6" select="substring($leader,7,1)"/>
		<xsl:variable name="leader7" select="substring($leader,8,1)"/>
		<xsl:variable name="controlField008" select="marc:controlfield[@tag='008']"/>
		<xsl:variable name="typeOf008">
			<xsl:choose>
				<xsl:when test="$leader6='a'">
					<xsl:choose>
						<xsl:when
							test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'">BK</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'">SE</xsl:when>
					</xsl:choose>
				</xsl:when>
				<xsl:when test="$leader6='t'">BK</xsl:when>
				<xsl:when test="$leader6='p'">MM</xsl:when>
				<xsl:when test="$leader6='m'">CF</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">MP</xsl:when>
				<xsl:when test="$leader6='g' or $leader6='k' or $leader6='o' or $leader6='r'">VM</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d' or $leader6='i' or $leader6='j'"
				>MU</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:for-each select="marc:datafield[@tag='245']">
			<titleInfo>
				<xsl:variable name="title">
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='b']">
							<xsl:call-template name="specialSubfieldSelect">
								<xsl:with-param name="axis">b</xsl:with-param>
								<xsl:with-param name="beforeCodes">afgk</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">abfgk</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="$title"/>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<xsl:choose>
					<xsl:when test="@ind2&gt;0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind2)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind2+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop"/>
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:if test="marc:subfield[@code='b']">
					<subTitle>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="axis">b</xsl:with-param>
									<xsl:with-param name="anyCodes">b</xsl:with-param>
									<xsl:with-param name="afterCodes">afgk</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</subTitle>
				</xsl:if>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='210']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='242']">
			<titleInfo type="translated">
				<!--09/01/04 Added subfield $y-->
				<xsl:for-each select="marc:subfield[@code='y']">
					<xsl:attribute name="lang">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='i']">
					<xsl:attribute name="displayLabel">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, b -->
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<!-- 1/04 fix -->
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='246']">
			<titleInfo type="alternative">
				<xsl:for-each select="marc:subfield[@code='i']">
					<xsl:attribute name="displayLabel">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, $b -->
								<xsl:with-param name="codes">af</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each
			select="marc:datafield[@tag='130']|marc:datafield[@tag='240']|marc:datafield[@tag='730'][@ind2!='2']">
			<titleInfo type="uniform">
				<title>
						<xsl:call-template name="uri"/>

					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if
								test="(contains('adfklmors',@code) and (not(../marc:subfield[@code='n' or @code='p']) or (following-sibling::marc:subfield[@code='n' or @code='p'])))">
								<xsl:value-of select="text()"/>
								<xsl:text> </xsl:text>
							</xsl:if>
						</xsl:for-each>
					</xsl:variable>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='740'][@ind2!='2']">
			<titleInfo type="alternative">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ah</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='100']">
			<name type="personal">

				<xsl:call-template name="uri"/>

				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='110']">
			<name type="corporate">

					<xsl:call-template name="uri"/>

				<xsl:call-template name="nameABCDN"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='111']">
			<name type="conference">

					<xsl:call-template name="uri"/>

				<xsl:call-template name="nameACDEQ"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='700'][not(marc:subfield[@code='t'])]">
			<name type="personal">

					<xsl:call-template name="uri"/>

				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='710'][not(marc:subfield[@code='t'])]">
			<name type="corporate">

					<xsl:call-template name="uri"/>

				<xsl:call-template name="nameABCDN"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='711'][not(marc:subfield[@code='t'])]">
			<name type="conference">

					<xsl:call-template name="uri"/>

				<xsl:call-template name="nameACDEQ"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='720'][not(marc:subfield[@code='t'])]">
			<name>
				<xsl:if test="@ind1=1">
					<xsl:attribute name="type">
						<xsl:text>personal</xsl:text>
					</xsl:attribute>
				</xsl:if>
				<namePart>
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</namePart>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<typeOfResource>
			<xsl:if test="$leader7='c'">
				<xsl:attribute name="collection">yes</xsl:attribute>
			</xsl:if>
			<xsl:if test="$leader6='d' or $leader6='f' or $leader6='p' or $leader6='t'">
				<xsl:attribute name="manuscript">yes</xsl:attribute>
			</xsl:if>
			<xsl:choose>
				<xsl:when test="$leader6='a' or $leader6='t'">text</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">cartographic</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d'">notated music</xsl:when>
				<xsl:when test="$leader6='i'">sound recording-nonmusical</xsl:when>
				<xsl:when test="$leader6='j'">sound recording-musical</xsl:when>
				<xsl:when test="$leader6='k'">still image</xsl:when>
				<xsl:when test="$leader6='g'">moving image</xsl:when>
				<xsl:when test="$leader6='r'">three dimensional object</xsl:when>
				<xsl:when test="$leader6='m'">software, multimedia</xsl:when>
				<xsl:when test="$leader6='p'">mixed material</xsl:when>
			</xsl:choose>
		</typeOfResource>
		<xsl:if test="substring($controlField008,26,1)='d'">
			<genre authority="marcgt">globe</genre>
		</xsl:if>
		<xsl:if
			test="marc:controlfield[@tag='007'][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
			<genre authority="marcgt">remote-sensing image</genre>
		</xsl:if>
		<xsl:if test="$typeOf008='MP'">
			<xsl:variable name="controlField008-25" select="substring($controlField008,26,1)"/>
			<xsl:choose>
				<xsl:when
					test="$controlField008-25='a' or $controlField008-25='b' or $controlField008-25='c' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
					<genre authority="marcgt">map</genre>
				</xsl:when>
				<xsl:when
					test="$controlField008-25='e' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
					<genre authority="marcgt">atlas</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='SE'">
			<xsl:variable name="controlField008-21" select="substring($controlField008,22,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-21='d'">
					<genre authority="marcgt">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='l'">
					<genre authority="marcgt">loose-leaf</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='m'">
					<genre authority="marcgt">series</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='n'">
					<genre authority="marcgt">newspaper</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='p'">
					<genre authority="marcgt">periodical</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='w'">
					<genre authority="marcgt">web site</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK' or $typeOf008='SE'">
			<xsl:variable name="controlField008-24" select="substring($controlField008,25,4)"/>
			<xsl:choose>
				<xsl:when test="contains($controlField008-24,'a')">
					<genre authority="marcgt">abstract or summary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'b')">
					<genre authority="marcgt">bibliography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'c')">
					<genre authority="marcgt">catalog</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'d')">
					<genre authority="marcgt">dictionary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'e')">
					<genre authority="marcgt">encyclopedia</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'f')">
					<genre authority="marcgt">handbook</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'g')">
					<genre authority="marcgt">legal article</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'i')">
					<genre authority="marcgt">index</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'k')">
					<genre authority="marcgt">discography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'l')">
					<genre authority="marcgt">legislation</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'m')">
					<genre authority="marcgt">theses</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'n')">
					<genre authority="marcgt">survey of literature</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'o')">
					<genre authority="marcgt">review</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'p')">
					<genre authority="marcgt">programmed text</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'q')">
					<genre authority="marcgt">filmography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'r')">
					<genre authority="marcgt">directory</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'s')">
					<genre authority="marcgt">statistics</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'t')">
					<genre authority="marcgt">technical report</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'v')">
					<genre authority="marcgt">legal case and case notes</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'w')">
					<genre authority="marcgt">law report or digest</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'z')">
					<genre authority="marcgt">treaty</genre>
				</xsl:when>
			</xsl:choose>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-29='1'">
					<genre authority="marcgt">conference publication</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='CF'">
			<xsl:variable name="controlField008-26" select="substring($controlField008,27,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-26='a'">
					<genre authority="marcgt">numeric data</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='e'">
					<genre authority="marcgt">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='f'">
					<genre authority="marcgt">font</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='g'">
					<genre authority="marcgt">game</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK'">
			<xsl:if test="substring($controlField008,25,1)='j'">
				<genre authority="marcgt">patent</genre>
			</xsl:if>
			<xsl:if test="substring($controlField008,25,1)='2'">
				<genre authority="marcgt">offprint</genre>
			</xsl:if>
			<xsl:if test="substring($controlField008,31,1)='1'">
				<genre authority="marcgt">festschrift</genre>
			</xsl:if>
			<xsl:variable name="controlField008-34" select="substring($controlField008,35,1)"/>
			<xsl:if
				test="$controlField008-34='a' or $controlField008-34='b' or $controlField008-34='c' or $controlField008-34='d'">
				<genre authority="marcgt">biography</genre>
			</xsl:if>
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-33='e'">
					<genre authority="marcgt">essay</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marcgt">drama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marcgt">comic strip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marcgt">fiction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='h'">
					<genre authority="marcgt">humor, satire</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marcgt">letter</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marcgt">novel</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='j'">
					<genre authority="marcgt">short story</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marcgt">speech</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='MU'">
			<xsl:variable name="controlField008-30-31" select="substring($controlField008,31,2)"/>
			<xsl:if test="contains($controlField008-30-31,'b')">
				<genre authority="marcgt">biography</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'c')">
				<genre authority="marcgt">conference publication</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'d')">
				<genre authority="marcgt">drama</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'e')">
				<genre authority="marcgt">essay</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'f')">
				<genre authority="marcgt">fiction</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'o')">
				<genre authority="marcgt">folktale</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'h')">
				<genre authority="marcgt">history</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'k')">
				<genre authority="marcgt">humor, satire</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'m')">
				<genre authority="marcgt">memoir</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'p')">
				<genre authority="marcgt">poetry</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'r')">
				<genre authority="marcgt">rehearsal</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'g')">
				<genre authority="marcgt">reporting</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'s')">
				<genre authority="marcgt">sound</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'l')">
				<genre authority="marcgt">speech</genre>
			</xsl:if>
		</xsl:if>
		<xsl:if test="$typeOf008='VM'">
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"/>
			<xsl:choose>
				<xsl:when test="$controlField008-33='a'">
					<genre authority="marcgt">art original</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='b'">
					<genre authority="marcgt">kit</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marcgt">art reproduction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marcgt">diorama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marcgt">filmstrip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='g'">
					<genre authority="marcgt">legal article</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marcgt">picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='k'">
					<genre authority="marcgt">graphic</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marcgt">technical drawing</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='m'">
					<genre authority="marcgt">motion picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='n'">
					<genre authority="marcgt">chart</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='o'">
					<genre authority="marcgt">flash card</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='p'">
					<genre authority="marcgt">microscope slide</genre>
				</xsl:when>
				<xsl:when
					test="$controlField008-33='q' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
					<genre authority="marcgt">model</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='r'">
					<genre authority="marcgt">realia</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marcgt">slide</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='t'">
					<genre authority="marcgt">transparency</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='v'">
					<genre authority="marcgt">videorecording</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='w'">
					<genre authority="marcgt">toy</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>

		<!-- 1.20 047 genre tmee-->

		<xsl:for-each select="marc:datafield[@tag=047]">
			<genre authority="marcgt">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcdef</xsl:with-param>
					<xsl:with-param name="delimeter">-</xsl:with-param>
				</xsl:call-template>
			</genre>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=655]">
			<genre authority="marcgt">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abvxyz</xsl:with-param>
					<xsl:with-param name="delimeter">-</xsl:with-param>
				</xsl:call-template>
			</genre>
		</xsl:for-each>
		<originInfo>
			<xsl:variable name="MARCpublicationCode"
				select="normalize-space(substring($controlField008,16,3))"/>
			<xsl:if test="translate($MARCpublicationCode,'|','')">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">marccountry</xsl:attribute>
						<xsl:value-of select="$MARCpublicationCode"/>
					</placeTerm>
				</place>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=044]/marc:subfield[@code='c']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">iso3166</xsl:attribute>
						<xsl:value-of select="."/>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=260]/marc:subfield[@code='a']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">text</xsl:attribute>
						<xsl:call-template name="chopPunctuationFront">
							<xsl:with-param name="chopString">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."/>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='m']">
				<dateValid point="start">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='n']">
				<dateValid point="end">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='j']">
				<dateModified>
					<xsl:value-of select="."/>
				</dateModified>
			</xsl:for-each>
			<xsl:for-each
				select="marc:datafield[@tag=260]/marc:subfield[@code='b' or @code='c' or @code='g']">
				<xsl:choose>
					<xsl:when test="@code='b'">
						<publisher>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
								<xsl:with-param name="punctuation">
									<xsl:text>:,;/ </xsl:text>
								</xsl:with-param>
							</xsl:call-template>
						</publisher>
					</xsl:when>
					<xsl:when test="@code='c'">
						<dateIssued>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</dateIssued>
					</xsl:when>
					<xsl:when test="@code='g'">
						<dateCreated>
							<xsl:value-of select="."/>
						</dateCreated>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<xsl:variable name="dataField260c">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString"
						select="marc:datafield[@tag=260]/marc:subfield[@code='c']"/>
				</xsl:call-template>
			</xsl:variable>
			<xsl:variable name="controlField008-7-10"
				select="normalize-space(substring($controlField008, 8, 4))"/>
			<xsl:variable name="controlField008-11-14"
				select="normalize-space(substring($controlField008, 12, 4))"/>
			<xsl:variable name="controlField008-6"
				select="normalize-space(substring($controlField008, 7, 1))"/>
			<xsl:if
				test="$controlField008-6='e' or $controlField008-6='p' or $controlField008-6='r' or $controlField008-6='t' or $controlField008-6='s'">
				<xsl:if test="$controlField008-7-10 and ($controlField008-7-10 != $dataField260c)">
					<dateIssued encoding="marc">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if
				test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if
				test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start" qualifier="questionable">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end" qualifier="questionable">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='t'">
				<xsl:if test="$controlField008-11-14">
					<copyrightDate encoding="marc">
						<xsl:value-of select="$controlField008-11-14"/>
					</copyrightDate>
				</xsl:if>
			</xsl:if>
			<xsl:for-each
				select="marc:datafield[@tag=033][@ind1=0 or @ind1=1]/marc:subfield[@code='a']">
				<dateCaptured encoding="iso8601">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][1]">
				<dateCaptured encoding="iso8601" point="start">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][2]">
				<dateCaptured encoding="iso8601" point="end">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=250]/marc:subfield[@code='a']">
				<edition>
					<xsl:value-of select="."/>
				</edition>
			</xsl:for-each>
			<xsl:for-each select="marc:leader">
				<issuance>
					<xsl:choose>
						<xsl:when
							test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'"
							>monographic</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'"
						>continuing</xsl:when>
					</xsl:choose>
				</issuance>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=310]|marc:datafield[@tag=321]">
				<frequency>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">ab</xsl:with-param>
					</xsl:call-template>
				</frequency>
			</xsl:for-each>
		</originInfo>
		<xsl:variable name="controlField008-35-37"
			select="normalize-space(translate(substring($controlField008,36,3),'|#',''))"/>
		<xsl:if test="$controlField008-35-37">
			<language>
				<languageTerm authority="iso639-2b" type="code">
					<xsl:value-of select="substring($controlField008,36,3)"/>
				</languageTerm>
			</language>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=041]">
			<xsl:for-each
				select="marc:subfield[@code='a' or @code='b' or @code='d' or @code='e' or @code='f' or @code='g' or @code='h']">
				<xsl:variable name="langCodes" select="."/>
				<xsl:choose>
					<xsl:when test="../marc:subfield[@code='2']='rfc3066'">
						<!-- not stacked but could be repeated -->
						<xsl:call-template name="rfcLanguages">
							<xsl:with-param name="nodeNum">
								<xsl:value-of select="1"/>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:text/>
							</xsl:with-param>
							<xsl:with-param name="controlField008-35-37">
								<xsl:value-of select="$controlField008-35-37"/>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:when>
					<xsl:otherwise>
						<!-- iso -->
						<xsl:variable name="allLanguages">
							<xsl:copy-of select="$langCodes"/>
						</xsl:variable>
						<xsl:variable name="currentLanguage">
							<xsl:value-of select="substring($allLanguages,1,3)"/>
						</xsl:variable>
						<xsl:call-template name="isoLanguage">
							<xsl:with-param name="currentLanguage">
								<xsl:value-of select="substring($allLanguages,1,3)"/>
							</xsl:with-param>
							<xsl:with-param name="remainingLanguages">
								<xsl:value-of
									select="substring($allLanguages,4,string-length($allLanguages)-3)"
								/>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:if test="$controlField008-35-37">
									<xsl:value-of select="$controlField008-35-37"/>
								</xsl:if>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:variable name="physicalDescription">
			<!--3.2 change tmee 007/11 -->
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='a']">
				<digitalOrigin>reformatted digital</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='b']">
				<digitalOrigin>digitized microfilm</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='d']">
				<digitalOrigin>digitized other analog</digitalOrigin>
			</xsl:if>
			<xsl:variable name="controlField008-23" select="substring($controlField008,24,1)"/>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"/>
			<xsl:variable name="check008-23">
				<xsl:if
					test="$typeOf008='BK' or $typeOf008='MU' or $typeOf008='SE' or $typeOf008='MM'">
					<xsl:value-of select="true()"/>
				</xsl:if>
			</xsl:variable>
			<xsl:variable name="check008-29">
				<xsl:if test="$typeOf008='MP' or $typeOf008='VM'">
					<xsl:value-of select="true()"/>
				</xsl:if>
			</xsl:variable>
			<xsl:choose>
				<xsl:when
					test="($check008-23 and $controlField008-23='f') or ($check008-29 and $controlField008-29='f')">
					<form authority="marcform">braille</form>
				</xsl:when>
				<xsl:when
					test="($controlField008-23=' ' and ($leader6='c' or $leader6='d')) or (($typeOf008='BK' or $typeOf008='SE') and ($controlField008-23=' ' or $controlField008='r'))">
					<form authority="marcform">print</form>
				</xsl:when>
				<xsl:when
					test="$leader6 = 'm' or ($check008-23 and $controlField008-23='s') or ($check008-29 and $controlField008-29='s')">
					<form authority="marcform">electronic</form>
				</xsl:when>
				<xsl:when
					test="($check008-23 and $controlField008-23='b') or ($check008-29 and $controlField008-29='b')">
					<form authority="marcform">microfiche</form>
				</xsl:when>
				<xsl:when
					test="($check008-23 and $controlField008-23='a') or ($check008-29 and $controlField008-29='a')">
					<form authority="marcform">microfilm</form>
				</xsl:when>
			</xsl:choose>
			<!-- 1/04 fix -->
			<xsl:if test="marc:datafield[@tag=130]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=130]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=240]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=240]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=242]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=242]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=245]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=245]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=246]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=246]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=730]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=730]/marc:subfield[@code='h']"
							/>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=256]/marc:subfield[@code='a']">
				<form>
					<xsl:value-of select="."/>
				</form>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=007][substring(text(),1,1)='c']">
				<xsl:choose>
					<xsl:when test="substring(text(),14,1)='a'">
						<reformattingQuality>access</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='p'">
						<reformattingQuality>preservation</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='r'">
						<reformattingQuality>replacement</reformattingQuality>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<!--3.2 change tmee 007/01 -->
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='b']">
				<form authority="smd">chip cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='c']">
				<form authority="smd">computer optical disc cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='j']">
				<form authority="smd">magnetic disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='m']">
				<form authority="smd">magneto-optical disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='o']">
				<form authority="smd">optical disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='r']">
				<form authority="smd">remote</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='a']">
				<form authority="smd">tape cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='f']">
				<form authority="smd">tape cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='h']">
				<form authority="smd">tape reel</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='a']">
				<form authority="smd">celestial globe</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='e']">
				<form authority="smd">earth moon globe</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='b']">
				<form authority="smd">planetary or lunar globe</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='c']">
				<form authority="smd">terrestrial globe</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='o'][substring(text(),2,1)='o']">
				<form authority="smd">kit</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
				<form authority="smd">atlas</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='g']">
				<form authority="smd">diagram</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
				<form authority="smd">map</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
				<form authority="smd">model</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='k']">
				<form authority="smd">profile</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='s']">
				<form authority="smd">section</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='y']">
				<form authority="smd">view</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='a']">
				<form authority="smd">aperture card</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='e']">
				<form authority="smd">microfiche</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='f']">
				<form authority="smd">microfiche cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='b']">
				<form authority="smd">microfilm cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='c']">
				<form authority="smd">microfilm cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='d']">
				<form authority="smd">microfilm reel</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='g']">
				<form authority="smd">microopaque</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='c']">
				<form authority="smd">film cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='f']">
				<form authority="smd">film cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='r']">
				<form authority="smd">film reel</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='n']">
				<form authority="smd">chart</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='c']">
				<form authority="smd">collage</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='d']">
				<form authority="smd">drawing</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='o']">
				<form authority="smd">flash card</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='e']">
				<form authority="smd">painting</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='f']">
				<form authority="smd">photomechanical print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='g']">
				<form authority="smd">photonegative</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='h']">
				<form authority="smd">photoprint</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='i']">
				<form authority="smd">picture</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='j']">
				<form authority="smd">print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='l']">
				<form authority="smd">technical drawing</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='q'][substring(text(),2,1)='q']">
				<form authority="smd">notated music</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='d']">
				<form authority="smd">filmslip</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='c']">
				<form authority="smd">filmstrip cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='o']">
				<form authority="smd">filmstrip roll</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='f']">
				<form authority="smd">other filmstrip type</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='s']">
				<form authority="smd">slide</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='t']">
				<form authority="smd">transparency</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='r'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='e']">
				<form authority="smd">cylinder</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='q']">
				<form authority="smd">roll</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='g']">
				<form authority="smd">sound cartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='s']">
				<form authority="smd">sound cassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='d']">
				<form authority="smd">sound disc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='t']">
				<form authority="smd">sound-tape reel</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='i']">
				<form authority="smd">sound-track film</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='w']">
				<form authority="smd">wire recording</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='b']">
				<form authority="smd">combination</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='a']">
				<form authority="smd">moon</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='d']">
				<form authority="smd">tactile, with no writing system</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='b']">
				<form authority="smd">large print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='a']">
				<form authority="smd">regular print</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='d']">
				<form authority="smd">text in looseleaf binder</form>
			</xsl:if>

			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='c']">
				<form authority="smd">videocartridge</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='f']">
				<form authority="smd">videocassette</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='d']">
				<form authority="smd">videodisc</form>
			</xsl:if>
			<xsl:if
				test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='r']">
				<form authority="smd">videoreel</form>
			</xsl:if>

			<xsl:for-each
				select="marc:datafield[@tag=856]/marc:subfield[@code='q'][string-length(.)&gt;1]">
				<internetMediaType>
					<xsl:value-of select="."/>
				</internetMediaType>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=300]">
				<extent>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abce</xsl:with-param>
					</xsl:call-template>
				</extent>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($physicalDescription))">
			<physicalDescription>
				<xsl:copy-of select="$physicalDescription"/>
			</physicalDescription>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=520]">
			<abstract>
				<xsl:call-template name="uri"/>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</abstract>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=505]">
			<tableOfContents>
				<xsl:call-template name="uri"/>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">agrt</xsl:with-param>
				</xsl:call-template>
			</tableOfContents>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=521]">
			<targetAudience>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</targetAudience>
		</xsl:for-each>
		<xsl:if test="$typeOf008='BK' or $typeOf008='CF' or $typeOf008='MU' or $typeOf008='VM'">
			<xsl:variable name="controlField008-22" select="substring($controlField008,23,1)"/>
			<xsl:choose>
				<!-- 01/04 fix -->
				<xsl:when test="$controlField008-22='d'">
					<targetAudience authority="marctarget">adolescent</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='e'">
					<targetAudience authority="marctarget">adult</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='g'">
					<targetAudience authority="marctarget">general</targetAudience>
				</xsl:when>
				<xsl:when
					test="$controlField008-22='b' or $controlField008-22='c' or $controlField008-22='j'">
					<targetAudience authority="marctarget">juvenile</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='a'">
					<targetAudience authority="marctarget">preschool</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='f'">
					<targetAudience authority="marctarget">specialized</targetAudience>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=245]/marc:subfield[@code='c']">
			<note type="statement of responsibility">
				<xsl:value-of select="."/>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=500]">
			<note>
				<xsl:value-of select="marc:subfield[@code='a']"/>
				<xsl:call-template name="uri"/>
			</note>
		</xsl:for-each>

		<!--3.2 change tmee additional note fields-->

		<xsl:for-each select="marc:datafield[@tag=506]">
			<note type="restrictions">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=510]">
			<note type="citation/reference">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>


		<xsl:for-each select="marc:datafield[@tag=511]">
			<note type="performers">
				<xsl:call-template name="uri"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=518]">
			<note type="venue">
				<xsl:call-template name="uri"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=530]">
			<note type="additional physical form">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=533]">
			<note type="reproduction">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=534]">
			<note type="original version">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=538]">
			<note type="system details">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=583]">
			<note type="action">
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>

		<xsl:for-each
			select="marc:datafield[@tag=501 or @tag=502 or @tag=504 or @tag=507 or @tag=508 or  @tag=513 or @tag=514 or @tag=515 or @tag=516 or @tag=522 or @tag=524 or @tag=525 or @tag=526 or @tag=535 or @tag=536 or @tag=540 or @tag=541 or @tag=544 or @tag=545 or @tag=546 or @tag=547 or @tag=550 or @tag=552 or @tag=555 or @tag=556 or @tag=561 or @tag=562 or @tag=565 or @tag=567 or @tag=580 or @tag=581 or @tag=584 or @tag=585 or @tag=586]">
			<note>
				<xsl:call-template name="uri"/>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."/>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
			</note>
		</xsl:for-each>
		<xsl:for-each
			select="marc:datafield[@tag=034][marc:subfield[@code='d' or @code='e' or @code='f' or @code='g']]">
			<subject>
				<cartographics>
					<coordinates>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">defg</xsl:with-param>
						</xsl:call-template>
					</coordinates>
				</cartographics>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=043]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
					<geographicCode>
						<xsl:attribute name="authority">
							<xsl:if test="@code='a'">
								<xsl:text>marcgac</xsl:text>
							</xsl:if>
							<xsl:if test="@code='b'">
								<xsl:value-of select="following-sibling::marc:subfield[@code=2]"/>
							</xsl:if>
							<xsl:if test="@code='c'">
								<xsl:text>iso3166</xsl:text>
							</xsl:if>
						</xsl:attribute>
						<xsl:value-of select="self::marc:subfield"/>
					</geographicCode>
				</xsl:for-each>
			</subject>
		</xsl:for-each>
		<!-- tmee 2006/11/27 -->
		<xsl:for-each select="marc:datafield[@tag=255]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
					<cartographics>
						<xsl:if test="@code='a'">
							<scale>
								<xsl:value-of select="."/>
							</scale>
						</xsl:if>
						<xsl:if test="@code='b'">
							<projection>
								<xsl:value-of select="."/>
							</projection>
						</xsl:if>
						<xsl:if test="@code='c'">
							<coordinates>
								<xsl:value-of select="."/>
							</coordinates>
						</xsl:if>
					</cartographics>
				</xsl:for-each>
			</subject>
		</xsl:for-each>

		<xsl:apply-templates select="marc:datafield[653 &gt;= @tag and @tag &gt;= 600]"/>
		<xsl:apply-templates select="marc:datafield[@tag=656]"/>
		<xsl:for-each select="marc:datafield[@tag=752 or @tag=662]">
			<subject>
				<hierarchicalGeographic>
					<xsl:for-each select="marc:subfield[@code='a']">
						<country>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</country>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<state>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</state>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='c']">
						<county>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</county>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='d']">
						<city>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</city>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='e']">
						<citySection>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</citySection>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='g']">
						<region>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</region>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='h']">
						<extraterrestrialArea>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</extraterrestrialArea>
					</xsl:for-each>
				</hierarchicalGeographic>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=045][marc:subfield[@code='b']]">
			<subject>
				<xsl:choose>
					<xsl:when test="@ind1=2">
						<temporal encoding="iso8601" point="start">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][1]"/>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
						<temporal encoding="iso8601" point="end">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][2]"/>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
					</xsl:when>
					<xsl:otherwise>
						<xsl:for-each select="marc:subfield[@code='b']">
							<temporal encoding="iso8601">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."/>
								</xsl:call-template>
							</temporal>
						</xsl:for-each>
					</xsl:otherwise>
				</xsl:choose>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=050]">
			<xsl:for-each select="marc:subfield[@code='b']">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"/>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="preceding-sibling::marc:subfield[@code='a'][1]"/>
					<xsl:text> </xsl:text>
					<xsl:value-of select="text()"/>
				</classification>
			</xsl:for-each>
			<xsl:for-each
				select="marc:subfield[@code='a'][not(following-sibling::marc:subfield[@code='b'])]">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"/>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="text()"/>
				</classification>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=082]">
			<classification authority="ddc">
				<xsl:if test="marc:subfield[@code='2']">
					<xsl:attribute name="edition">
						<xsl:value-of select="marc:subfield[@code='2']"/>
					</xsl:attribute>
				</xsl:if>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=080]">
			<classification authority="udc">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abx</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=060]">
			<classification authority="nlm">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=0]">
			<classification authority="sudocs">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=1]">
			<classification authority="candoc">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=084]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=440]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=490][@ind1=0]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=510]">
			<relatedItem type="isReferencedBy">
				<note>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcx3</xsl:with-param>
					</xsl:call-template>
				</note>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=534]">
			<relatedItem type="original">
				<xsl:call-template name="relatedTitle"/>
				<xsl:call-template name="relatedName"/>
				<xsl:if test="marc:subfield[@code='b' or @code='c']">
					<originInfo>
						<xsl:for-each select="marc:subfield[@code='c']">
							<publisher>
								<xsl:value-of select="."/>
							</publisher>
						</xsl:for-each>
						<xsl:for-each select="marc:subfield[@code='b']">
							<edition>
								<xsl:value-of select="."/>
							</edition>
						</xsl:for-each>
					</originInfo>
				</xsl:if>
				<xsl:call-template name="relatedIdentifierISSN"/>
				<xsl:for-each select="marc:subfield[@code='z']">
					<identifier type="isbn">
						<xsl:value-of select="."/>
					</identifier>
				</xsl:for-each>
				<xsl:call-template name="relatedNote"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=700][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aq</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">g</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"/>
					<xsl:call-template name="nameDate"/>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=710][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<xsl:variable name="tempNamePart">
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</xsl:variable>
					<xsl:if test="normalize-space($tempNamePart)">
						<namePart>
							<xsl:value-of select="$tempNamePart"/>
						</namePart>
					</xsl:if>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=711][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</name>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=730][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
				<xsl:call-template name="relatedIdentifierISSN"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=740][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"/>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:value-of select="marc:subfield[@code='a']"/>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=760]|marc:datafield[@tag=762]">
			<relatedItem type="series">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each
			select="marc:datafield[@tag=765]|marc:datafield[@tag=767]|marc:datafield[@tag=777]|marc:datafield[@tag=787]">
			<relatedItem>
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=775]">
			<relatedItem type="otherVersion">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=770]|marc:datafield[@tag=774]">
			<relatedItem type="constituent">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=772]|marc:datafield[@tag=773]">
			<relatedItem type="host">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=776]">
			<relatedItem type="otherFormat">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=780]">
			<relatedItem type="preceding">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=785]">
			<relatedItem type="succeeding">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=786]">
			<relatedItem type="original">
				<xsl:call-template name="relatedItem76X-78X"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=800]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">aq</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="beforeCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"/>
					<xsl:call-template name="nameDate"/>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=810]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."/>
						</namePart>
					</xsl:for-each>
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=811]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='830']">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][@ind2='2']/marc:subfield[@code='q']">
			<relatedItem>
				<internetMediaType>
					<xsl:value-of select="."/>
				</internetMediaType>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='020']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isbn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isbn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='0']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isrc</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isrc">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='2']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">ismn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="ismn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='4']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">sici</xsl:with-param>
			</xsl:call-template>
			<identifier type="sici">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='022']">
			<xsl:if test="marc:subfield[@code='a']">
				<xsl:call-template name="isInvalid">
					<xsl:with-param name="type">issn</xsl:with-param>
				</xsl:call-template>
				<identifier type="issn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
			<xsl:if test="marc:subfield[@code='l']">
				<xsl:call-template name="isInvalid">
					<xsl:with-param name="type">issn-l</xsl:with-param>
				</xsl:call-template>
				<identifier type="issn-l">
					<xsl:value-of select="marc:subfield[@code='l']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>



		<xsl:for-each select="marc:datafield[@tag='010']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">lccn</xsl:with-param>
			</xsl:call-template>
			<identifier type="lccn">
				<xsl:value-of select="normalize-space(marc:subfield[@code='a'])"/>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='028']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when test="@ind1='0'">issue number</xsl:when>
						<xsl:when test="@ind1='1'">matrix number</xsl:when>
						<xsl:when test="@ind1='2'">music plate</xsl:when>
						<xsl:when test="@ind1='3'">music publisher</xsl:when>
						<xsl:when test="@ind1='4'">videorecording identifier</xsl:when>
					</xsl:choose>
				</xsl:attribute>
				<!--<xsl:call-template name="isInvalid"/>-->
				<!-- no $z in 028 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">
						<xsl:choose>
							<xsl:when test="@ind1='0'">ba</xsl:when>
							<xsl:otherwise>ab</xsl:otherwise>
						</xsl:choose>
					</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='037']">
			<identifier type="stock number">
				<!--<xsl:call-template name="isInvalid"/>-->
				<!-- no $z in 037 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][marc:subfield[@code='u']]">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when
							test="starts-with(marc:subfield[@code='u'],'urn:doi') or starts-with(marc:subfield[@code='u'],'doi')"
							>doi</xsl:when>
						<xsl:when
							test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov')"
							>hdl</xsl:when>
						<xsl:otherwise>uri</xsl:otherwise>
					</xsl:choose>
				</xsl:attribute>
				<xsl:choose>
					<xsl:when
						test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov') ">
						<xsl:value-of
							select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"
						/>
					</xsl:when>
					<xsl:otherwise>
						<xsl:value-of select="marc:subfield[@code='u']"/>
					</xsl:otherwise>
				</xsl:choose>
			</identifier>
			<xsl:if
				test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl')">
				<identifier type="hdl">
					<xsl:if test="marc:subfield[@code='y' or @code='3' or @code='z']">
						<xsl:attribute name="displayLabel">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">y3z</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of
						select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"
					/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=024][@ind1=1]">
			<identifier type="upc">
				<xsl:call-template name="isInvalid"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</identifier>
		</xsl:for-each>

		<!-- 1/04 fix added $y -->

		<!-- 1.21  tmee-->
		<xsl:for-each select="marc:datafield[@tag=856][@ind2=1][marc:subfield[@code='u']]">
			<relatedItem type="otherVersion">
				<location>
					<url>
						<xsl:if test="marc:subfield[@code='y' or @code='3']">
							<xsl:attribute name="displayLabel">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">y3</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:if test="marc:subfield[@code='z' ]">
							<xsl:attribute name="note">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">z</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:value-of select="marc:subfield[@code='u']"/>
					</url>
				</location>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=856][@ind2=2][marc:subfield[@code='u']]">
			<relatedItem>
				<location>
					<url>
						<xsl:if test="marc:subfield[@code='y' or @code='3']">
							<xsl:attribute name="displayLabel">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">y3</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:if test="marc:subfield[@code='z' ]">
							<xsl:attribute name="note">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">z</xsl:with-param>
								</xsl:call-template>
							</xsl:attribute>
						</xsl:if>
						<xsl:value-of select="marc:subfield[@code='u']"/>
					</url>
				</location>
			</relatedItem>
		</xsl:for-each>

		<!-- 3.2 change tmee 856z  -->

		<!-- 1.24  tmee  -->
		<xsl:for-each select="marc:datafield[@tag=852]">
			<location>
				<xsl:if test="marc:subfield[@code='a' or @code='b' or @code='e']">
					<physicalLocation>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abe</xsl:with-param>
						</xsl:call-template>
					</physicalLocation>
				</xsl:if>

				<xsl:if test="marc:subfield[@code='u']">
					<physicalLocation>
						<xsl:call-template name="uri"/>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">u</xsl:with-param>
						</xsl:call-template>
					</physicalLocation>
				</xsl:if>

				<xsl:if
					test="marc:subfield[@code='h' or @code='i' or @code='j' or @code='k' or @code='l' or @code='m' or @code='t']">
					<shelfLocation>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">hijklmt</xsl:with-param>
						</xsl:call-template>
					</shelfLocation>
				</xsl:if>
			</location>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=506]">
			<accessCondition type="restrictionOnAccess">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcd35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=540]">
			<accessCondition type="useAndReproduction">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcde35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>

		<recordInfo>
			<!-- 1.25  tmee-->


			<xsl:for-each select="marc:leader[substring($leader,19,1)='a']">
				<descriptionStandard>aacr2</descriptionStandard>
			</xsl:for-each>

			<xsl:for-each select="marc:datafield[@tag=040]">
				<xsl:if test="marc:subfield[@code='e']">
					<descriptionStandard>
						<xsl:value-of select="marc:subfield[@code='e']"/>
					</descriptionStandard>
				</xsl:if>
				<recordContentSource authority="marcorg">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</recordContentSource>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=008]">
				<recordCreationDate encoding="marc">
					<xsl:value-of select="substring(.,1,6)"/>
				</recordCreationDate>
			</xsl:for-each>

			<xsl:for-each select="marc:controlfield[@tag=005]">
				<recordChangeDate encoding="iso8601">
					<xsl:value-of select="."/>
				</recordChangeDate>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=001]">
				<recordIdentifier>
					<xsl:if test="../marc:controlfield[@tag=003]">
						<xsl:attribute name="source">
							<xsl:value-of select="../marc:controlfield[@tag=003]"/>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="."/>
				</recordIdentifier>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=040]/marc:subfield[@code='b']">
				<languageOfCataloging>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="."/>
					</languageTerm>
				</languageOfCataloging>
			</xsl:for-each>
		</recordInfo>
	</xsl:template>
	<xsl:template name="displayForm">
		<xsl:for-each select="marc:subfield[@code='c']">
			<displayForm>
				<xsl:value-of select="."/>
			</displayForm>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="affiliation">
		<xsl:for-each select="marc:subfield[@code='u']">
			<affiliation>
				<xsl:value-of select="."/>
			</affiliation>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="uri">
		<xsl:for-each select="marc:subfield[@code='u']">
			<xsl:attribute name="xlink:href">
				<xsl:value-of select="."/>
			</xsl:attribute>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='0']">
			<xsl:choose>
				<xsl:when test="contains(text(), ')')">
					<xsl:attribute name="xlink:href">
						<xsl:value-of select="substring-after(text(), ')')"></xsl:value-of>
					</xsl:attribute>
				</xsl:when>
				<xsl:otherwise>
					<xsl:attribute name="xlink:href">
						<xsl:value-of select="."></xsl:value-of>
					</xsl:attribute>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="role">
		<xsl:for-each select="marc:subfield[@code='e']">
			<role>
				<roleTerm type="text">
					<xsl:value-of select="."/>
				</roleTerm>
			</role>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='4']">
			<role>
				<roleTerm authority="marcrelator" type="code">
					<xsl:value-of select="."/>
				</roleTerm>
			</role>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="part">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">n</xsl:with-param>
				<xsl:with-param name="anyCodes">n</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partNumber"/>
				</xsl:call-template>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partName"/>
				</xsl:call-template>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPart">
		<xsl:if test="@tag=773">
			<xsl:for-each select="marc:subfield[@code='g']">
				<part>
					<text>
						<xsl:value-of select="."/>
					</text>
				</part>
			</xsl:for-each>
			<xsl:for-each select="marc:subfield[@code='q']">
				<part>
					<xsl:call-template name="parsePart"/>
				</part>
			</xsl:for-each>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPartNumName">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">g</xsl:with-param>
				<xsl:with-param name="anyCodes">g</xsl:with-param>
				<xsl:with-param name="afterCodes">pst</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:value-of select="$partNumber"/>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:value-of select="$partName"/>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedName">
		<xsl:for-each select="marc:subfield[@code='a']">
			<name>
				<namePart>
					<xsl:value-of select="."/>
				</namePart>
			</name>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedForm">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<form>
					<xsl:value-of select="."/>
				</form>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedExtent">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<extent>
					<xsl:value-of select="."/>
				</extent>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedNote">
		<xsl:for-each select="marc:subfield[@code='n']">
			<note>
				<xsl:value-of select="."/>
			</note>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedSubject">
		<xsl:for-each select="marc:subfield[@code='j']">
			<subject>
				<temporal encoding="iso8601">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."/>
					</xsl:call-template>
				</temporal>
			</subject>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierISSN">
		<xsl:for-each select="marc:subfield[@code='x']">
			<identifier type="issn">
				<xsl:value-of select="."/>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierLocal">
		<xsl:for-each select="marc:subfield[@code='w']">
			<identifier type="local">
				<xsl:value-of select="."/>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifier">
		<xsl:for-each select="marc:subfield[@code='o']">
			<identifier>
				<xsl:value-of select="."/>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedItem76X-78X">
		<xsl:call-template name="displayLabel"/>
		<xsl:call-template name="relatedTitle76X-78X"/>
		<xsl:call-template name="relatedName"/>
		<xsl:call-template name="relatedOriginInfo"/>
		<xsl:call-template name="relatedLanguage"/>
		<xsl:call-template name="relatedExtent"/>
		<xsl:call-template name="relatedNote"/>
		<xsl:call-template name="relatedSubject"/>
		<xsl:call-template name="relatedIdentifier"/>
		<xsl:call-template name="relatedIdentifierISSN"/>
		<xsl:call-template name="relatedIdentifierLocal"/>
		<xsl:call-template name="relatedPart"/>
	</xsl:template>
	<xsl:template name="subjectGeographicZ">
		<geographic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</geographic>
	</xsl:template>
	<xsl:template name="subjectTemporalY">
		<temporal>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</temporal>
	</xsl:template>
	<xsl:template name="subjectTopic">
		<topic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</topic>
	</xsl:template>
	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template name="subjectGenre">
		<genre>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."/>
			</xsl:call-template>
		</genre>
	</xsl:template>

	<xsl:template name="nameABCDN">
		<xsl:for-each select="marc:subfield[@code='a']">
			<namePart>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='b']">
			<namePart>
				<xsl:value-of select="."/>
			</namePart>
		</xsl:for-each>
		<xsl:if
			test="marc:subfield[@code='c'] or marc:subfield[@code='d'] or marc:subfield[@code='n']">
			<namePart>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">cdn</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="nameABCDQ">
		<namePart>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">aq</xsl:with-param>
					</xsl:call-template>
				</xsl:with-param>
				<xsl:with-param name="punctuation">
					<xsl:text>:,;/ </xsl:text>
				</xsl:with-param>
			</xsl:call-template>
		</namePart>
		<xsl:call-template name="termsOfAddress"/>
		<xsl:call-template name="nameDate"/>
	</xsl:template>
	<xsl:template name="nameACDEQ">
		<namePart>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">acdeq</xsl:with-param>
			</xsl:call-template>
		</namePart>
	</xsl:template>
	<xsl:template name="constituentOrRelatedType">
		<xsl:if test="@ind2=2">
			<xsl:attribute name="type">constituent</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedTitle">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedTitle76X-78X">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"/>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='p']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"/>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='s']">
			<titleInfo type="uniform">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."/>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"/>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedOriginInfo">
		<xsl:if test="marc:subfield[@code='b' or @code='d'] or marc:subfield[@code='f']">
			<originInfo>
				<xsl:if test="@tag=775">
					<xsl:for-each select="marc:subfield[@code='f']">
						<place>
							<placeTerm>
								<xsl:attribute name="type">code</xsl:attribute>
								<xsl:attribute name="authority">marcgac</xsl:attribute>
								<xsl:value-of select="."/>
							</placeTerm>
						</place>
					</xsl:for-each>
				</xsl:if>
				<xsl:for-each select="marc:subfield[@code='d']">
					<publisher>
						<xsl:value-of select="."/>
					</publisher>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<edition>
						<xsl:value-of select="."/>
					</edition>
				</xsl:for-each>
			</originInfo>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedLanguage">
		<xsl:for-each select="marc:subfield[@code='e']">
			<xsl:call-template name="getLanguage">
				<xsl:with-param name="langString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="nameDate">
		<xsl:for-each select="marc:subfield[@code='d']">
			<namePart type="date">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="subjectAuthority">
		<xsl:if test="@ind2!=4">
			<xsl:if test="@ind2!=' '">
				<xsl:if test="@ind2!=8">
					<xsl:if test="@ind2!=9">
						<xsl:attribute name="authority">
							<xsl:choose>
								<xsl:when test="@ind2=0">lcsh</xsl:when>
								<xsl:when test="@ind2=1">lcshac</xsl:when>
								<xsl:when test="@ind2=2">mesh</xsl:when>
								<!-- 1/04 fix -->
								<xsl:when test="@ind2=3">nal</xsl:when>
								<xsl:when test="@ind2=5">csh</xsl:when>
								<xsl:when test="@ind2=6">rvm</xsl:when>
								<xsl:when test="@ind2=7">
									<xsl:value-of select="marc:subfield[@code='2']"/>
								</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
				</xsl:if>
			</xsl:if>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subjectAnyOrder">
		<xsl:for-each select="marc:subfield[@code='v' or @code='x' or @code='y' or @code='z']">
			<xsl:choose>
				<xsl:when test="@code='v'">
					<xsl:call-template name="subjectGenre"/>
				</xsl:when>
				<xsl:when test="@code='x'">
					<xsl:call-template name="subjectTopic"/>
				</xsl:when>
				<xsl:when test="@code='y'">
					<xsl:call-template name="subjectTemporalY"/>
				</xsl:when>
				<xsl:when test="@code='z'">
					<xsl:call-template name="subjectGeographicZ"/>
				</xsl:when>
			</xsl:choose>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="specialSubfieldSelect">
		<xsl:param name="anyCodes"/>
		<xsl:param name="axis"/>
		<xsl:param name="beforeCodes"/>
		<xsl:param name="afterCodes"/>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if
					test="contains($anyCodes, @code)      or (contains($beforeCodes,@code) and following-sibling::marc:subfield[@code=$axis])      or (contains($afterCodes,@code) and preceding-sibling::marc:subfield[@code=$axis])">
					<xsl:value-of select="text()"/>
					<xsl:text> </xsl:text>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
	</xsl:template>

	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template match="marc:datafield[@tag=600]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<name type="personal">
				<xsl:call-template name="termsOfAddress"/>
				<namePart>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">aq</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:call-template name="nameDate"/>
				<xsl:call-template name="affiliation"/>
				<xsl:call-template name="role"/>
			</name>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=610]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<name type="corporate">
				<xsl:for-each select="marc:subfield[@code='a']">
					<namePart>
						<xsl:value-of select="."/>
					</namePart>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<namePart>
						<xsl:value-of select="."/>
					</namePart>
				</xsl:for-each>
				<xsl:if test="marc:subfield[@code='c' or @code='d' or @code='n' or @code='p']">
					<namePart>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">cdnp</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</xsl:if>
				<xsl:call-template name="role"/>
			</name>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=611]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<name type="conference">
				<namePart>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcdeqnp</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:for-each select="marc:subfield[@code='4']">
					<role>
						<roleTerm authority="marcrelator" type="code">
							<xsl:value-of select="."/>
						</roleTerm>
					</role>
				</xsl:for-each>
			</name>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=630]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">adfhklor</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<!-- 1.27 648 tmee-->
	<xsl:template match="marc:datafield[@tag=648]">
		<subject>
			<xsl:if test="marc:subfield[@code=2]">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code=2]"/>
				</xsl:attribute>
			</xsl:if>
			<xsl:call-template name="uri"/>

			<xsl:call-template name="subjectAuthority"/>
			<temporal>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abcd</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</temporal>
			<xsl:call-template name="subjectAnyOrder"/>

		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=650]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<topic>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abcd</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</topic>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=651]">
		<subject>
			<xsl:call-template name="subjectAuthority"/>
			<xsl:for-each select="marc:subfield[@code='a']">
				<geographic>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."/>
					</xsl:call-template>
				</geographic>
			</xsl:for-each>
			<xsl:call-template name="subjectAnyOrder"/>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=653]">
		<subject>
			<xsl:for-each select="marc:subfield[@code='a']">
				<topic>
					<xsl:value-of select="."/>
				</topic>
			</xsl:for-each>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=656]">
		<subject>
			<xsl:if test="marc:subfield[@code=2]">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code=2]"/>
				</xsl:attribute>
			</xsl:if>
			<occupation>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</xsl:with-param>
				</xsl:call-template>
			</occupation>
		</subject>
	</xsl:template>
	<xsl:template name="termsOfAddress">
		<xsl:if test="marc:subfield[@code='b' or @code='c']">
			<namePart type="termsOfAddress">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">bc</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="displayLabel">
		<xsl:if test="marc:subfield[@code='i']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='i']"/>
			</xsl:attribute>
		</xsl:if>
		<xsl:if test="marc:subfield[@code='3']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='3']"/>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="isInvalid">
		<xsl:param name="type"/>
		<xsl:if
			test="marc:subfield[@code='z'] or marc:subfield[@code='y']  or marc:subfield[@code='m']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:value-of select="$type"/>
				</xsl:attribute>
				<xsl:attribute name="invalid">
					<xsl:text>yes</xsl:text>
				</xsl:attribute>
				<xsl:if test="marc:subfield[@code='z']">
					<xsl:value-of select="marc:subfield[@code='z']"/>
				</xsl:if>
				<xsl:if test="marc:subfield[@code='y']">
					<xsl:value-of select="marc:subfield[@code='y']"/>
				</xsl:if>
				<xsl:if test="marc:subfield[@code='m']">
					<xsl:value-of select="marc:subfield[@code='m']"/>
				</xsl:if>
			</identifier>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subtitle">
		<xsl:if test="marc:subfield[@code='b']">
			<subTitle>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='b']"/>
						<!--<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">b</xsl:with-param>									
						</xsl:call-template>-->
					</xsl:with-param>
				</xsl:call-template>
			</subTitle>
		</xsl:if>
	</xsl:template>
	<xsl:template name="script">
		<xsl:param name="scriptCode"/>
		<xsl:attribute name="script">
			<xsl:choose>
				<xsl:when test="$scriptCode='(3'">Arabic</xsl:when>
				<xsl:when test="$scriptCode='(B'">Latin</xsl:when>
				<xsl:when test="$scriptCode='$1'">Chinese, Japanese, Korean</xsl:when>
				<xsl:when test="$scriptCode='(N'">Cyrillic</xsl:when>
				<xsl:when test="$scriptCode='(2'">Hebrew</xsl:when>
				<xsl:when test="$scriptCode='(S'">Greek</xsl:when>
			</xsl:choose>
		</xsl:attribute>
	</xsl:template>
	<xsl:template name="parsePart">
		<!-- assumes 773$q= 1:2:3<4
		     with up to 3 levels and one optional start page
		-->
		<xsl:variable name="level1">
			<xsl:choose>
				<xsl:when test="contains(text(),':')">
					<!-- 1:2 -->
					<xsl:value-of select="substring-before(text(),':')"/>
				</xsl:when>
				<xsl:when test="not(contains(text(),':'))">
					<!-- 1 or 1<3 -->
					<xsl:if test="contains(text(),'&lt;')">
						<!-- 1<3 -->
						<xsl:value-of select="substring-before(text(),'&lt;')"/>
					</xsl:if>
					<xsl:if test="not(contains(text(),'&lt;'))">
						<!-- 1 -->
						<xsl:value-of select="text()"/>
					</xsl:if>
				</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici2">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after(text(),$level1),':')">
					<xsl:value-of select="substring(substring-after(text(),$level1),2)"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after(text(),$level1)"/>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level2">
			<xsl:choose>
				<xsl:when test="contains($sici2,':')">
					<!--  2:3<4  -->
					<xsl:value-of select="substring-before($sici2,':')"/>
				</xsl:when>
				<xsl:when test="contains($sici2,'&lt;')">
					<!-- 1: 2<4 -->
					<xsl:value-of select="substring-before($sici2,'&lt;')"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici2"/>
					<!-- 1:2 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici3">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after($sici2,$level2),':')">
					<xsl:value-of select="substring(substring-after($sici2,$level2),2)"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after($sici2,$level2)"/>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level3">
			<xsl:choose>
				<xsl:when test="contains($sici3,'&lt;')">
					<!-- 2<4 -->
					<xsl:value-of select="substring-before($sici3,'&lt;')"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici3"/>
					<!-- 3 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="page">
			<xsl:if test="contains(text(),'&lt;')">
				<xsl:value-of select="substring-after(text(),'&lt;')"/>
			</xsl:if>
		</xsl:variable>
		<xsl:if test="$level1">
			<detail level="1">
				<number>
					<xsl:value-of select="$level1"/>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level2">
			<detail level="2">
				<number>
					<xsl:value-of select="$level2"/>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level3">
			<detail level="3">
				<number>
					<xsl:value-of select="$level3"/>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$page">
			<extent unit="page">
				<start>
					<xsl:value-of select="$page"/>
				</start>
			</extent>
		</xsl:if>
	</xsl:template>
	<xsl:template name="getLanguage">
		<xsl:param name="langString"/>
		<xsl:param name="controlField008-35-37"/>
		<xsl:variable name="length" select="string-length($langString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="$controlField008-35-37=substring($langString,1,3)">
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"/>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<language>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="substring($langString,1,3)"/>
					</languageTerm>
				</language>
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"/>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"/>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="isoLanguage">
		<xsl:param name="currentLanguage"/>
		<xsl:param name="usedLanguages"/>
		<xsl:param name="remainingLanguages"/>
		<xsl:choose>
			<xsl:when test="string-length($currentLanguage)=0"/>
			<xsl:when test="not(contains($usedLanguages, $currentLanguage))">
				<language>
					<xsl:if test="@code!='a'">
						<xsl:attribute name="objectPart">
							<xsl:choose>
								<xsl:when test="@code='b'">summary or subtitle</xsl:when>
								<xsl:when test="@code='d'">sung or spoken text</xsl:when>
								<xsl:when test="@code='e'">libretto</xsl:when>
								<xsl:when test="@code='f'">table of contents</xsl:when>
								<xsl:when test="@code='g'">accompanying material</xsl:when>
								<xsl:when test="@code='h'">translation</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="$currentLanguage"/>
					</languageTerm>
				</language>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"/>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"/>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of
							select="substring($remainingLanguages,4,string-length($remainingLanguages))"
						/>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"/>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"/>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of
							select="substring($remainingLanguages,4,string-length($remainingLanguages))"
						/>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="chopBrackets">
		<xsl:param name="chopString"/>
		<xsl:variable name="string">
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="$chopString"/>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="substring($string, 1,1)='['">
			<xsl:value-of select="substring($string,2, string-length($string)-2)"/>
		</xsl:if>
		<xsl:if test="substring($string, 1,1)!='['">
			<xsl:value-of select="$string"/>
		</xsl:if>
	</xsl:template>
	<xsl:template name="rfcLanguages">
		<xsl:param name="nodeNum"/>
		<xsl:param name="usedLanguages"/>
		<xsl:param name="controlField008-35-37"/>
		<xsl:variable name="currentLanguage" select="."/>
		<xsl:choose>
			<xsl:when test="not($currentLanguage)"/>
			<xsl:when
				test="$currentLanguage!=$controlField008-35-37 and $currentLanguage!='rfc3066'">
				<xsl:if test="not(contains($usedLanguages,$currentLanguage))">
					<language>
						<xsl:if test="@code!='a'">
							<xsl:attribute name="objectPart">
								<xsl:choose>
									<xsl:when test="@code='b'">summary or subtitle</xsl:when>
									<xsl:when test="@code='d'">sung or spoken text</xsl:when>
									<xsl:when test="@code='e'">libretto</xsl:when>
									<xsl:when test="@code='f'">table of contents</xsl:when>
									<xsl:when test="@code='g'">accompanying material</xsl:when>
									<xsl:when test="@code='h'">translation</xsl:when>
								</xsl:choose>
							</xsl:attribute>
						</xsl:if>
						<languageTerm authority="rfc3066" type="code">
							<xsl:value-of select="$currentLanguage"/>
						</languageTerm>
					</language>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise> </xsl:otherwise>
		</xsl:choose>
	</xsl:template>

    <xsl:template name="datafield">
		<xsl:param name="tag"/>
		<xsl:param name="ind1">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="ind2">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="subfields"/>
		<xsl:element name="marc:datafield">
			<xsl:attribute name="tag">
				<xsl:value-of select="$tag"/>
			</xsl:attribute>
			<xsl:attribute name="ind1">
				<xsl:value-of select="$ind1"/>
			</xsl:attribute>
			<xsl:attribute name="ind2">
				<xsl:value-of select="$ind2"/>
			</xsl:attribute>
			<xsl:copy-of select="$subfields"/>
		</xsl:element>
	</xsl:template>

	<xsl:template name="subfieldSelect">
		<xsl:param name="codes">abcdefghijklmnopqrstuvwxyz</xsl:param>
		<xsl:param name="delimeter">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($codes, @code)">
					<xsl:value-of select="text()"/>
					<xsl:value-of select="$delimeter"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
	</xsl:template>

	<xsl:template name="buildSpaces">
		<xsl:param name="spaces"/>
		<xsl:param name="char">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:if test="$spaces>0">
			<xsl:value-of select="$char"/>
			<xsl:call-template name="buildSpaces">
				<xsl:with-param name="spaces" select="$spaces - 1"/>
				<xsl:with-param name="char" select="$char"/>
			</xsl:call-template>
		</xsl:if>
	</xsl:template>

	<xsl:template name="chopPunctuation">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/ </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationFront">
		<xsl:param name="chopString"/>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains('.:,;/[ ', substring($chopString,1,1))">
				<xsl:call-template name="chopPunctuationFront">
					<xsl:with-param name="chopString" select="substring($chopString,2,$length - 1)"
					/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationBack">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/] </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<!-- nate added 12/14/2007 for lccn.loc.gov: url encode ampersand, etc. -->
	<xsl:template name="url-encode">

		<xsl:param name="str"/>

		<xsl:if test="$str">
			<xsl:variable name="first-char" select="substring($str,1,1)"/>
			<xsl:choose>
				<xsl:when test="contains($safe,$first-char)">
					<xsl:value-of select="$first-char"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:variable name="codepoint">
						<xsl:choose>
							<xsl:when test="contains($ascii,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($ascii,$first-char)) + 32"
								/>
							</xsl:when>
							<xsl:when test="contains($latin1,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($latin1,$first-char)) + 160"/>
								<!-- was 160 -->
							</xsl:when>
							<xsl:otherwise>
								<xsl:message terminate="no">Warning: string contains a character
									that is out of range! Substituting "?".</xsl:message>
								<xsl:text>63</xsl:text>
							</xsl:otherwise>
						</xsl:choose>
					</xsl:variable>
					<xsl:variable name="hex-digit1"
						select="substring($hex,floor($codepoint div 16) + 1,1)"/>
					<xsl:variable name="hex-digit2" select="substring($hex,$codepoint mod 16 + 1,1)"/>
					<!-- <xsl:value-of select="concat('%',$hex-digit2)"/> -->
					<xsl:value-of select="concat('%',$hex-digit1,$hex-digit2)"/>
				</xsl:otherwise>
			</xsl:choose>
			<xsl:if test="string-length($str) &gt; 1">
				<xsl:call-template name="url-encode">
					<xsl:with-param name="str" select="substring($str,2)"/>
				</xsl:call-template>
			</xsl:if>
		</xsl:if>
	</xsl:template>
</xsl:stylesheet>$$ WHERE name = 'mods33';


INSERT INTO config.global_flag (name, value, enabled, label) VALUES
(
    'opac.browse.warnable_regexp_per_class',
    '{"title": "^(a|the|an)\\s"}',
    FALSE,
    oils_i18n_gettext(
        'opac.browse.warnable_regexp_per_class',
        'Map of search classes to regular expressions to warn user about leading articles.',
        'cgf',
        'label'
    )
),
(
    'opac.browse.holdings_visibility_test_limit',
    '100',
    TRUE,
    oils_i18n_gettext(
        'opac.browse.holdings_visibility_test_limit',
        'Don''t look for more than this number of records with holdings when displaying browse headings with visible record counts.',
        'cgf',
        'label'
    )
);

ALTER TABLE metabib.browse_entry DROP CONSTRAINT browse_entry_value_key;
ALTER TABLE metabib.browse_entry ADD COLUMN sort_value TEXT;
DELETE FROM metabib.browse_entry_def_map; -- Yeah.
DELETE FROM metabib.browse_entry WHERE sort_value IS NULL;
ALTER TABLE metabib.browse_entry ALTER COLUMN sort_value SET NOT NULL;
ALTER TABLE metabib.browse_entry ADD UNIQUE (sort_value, value);
DROP TRIGGER IF EXISTS mbe_sort_value ON metabib.browse_entry;

CREATE INDEX browse_entry_sort_value_idx
    ON metabib.browse_entry USING BTREE (sort_value);

-- NOTE If I understand ordered indices correctly, an index on sort_value DESC
-- is not actually needed, even though we do have a query that does ORDER BY
-- on this column in that direction.  The previous index serves for both
-- directions, and ordering in an index is only helpful for multi-column
-- indices, I think. See http://www.postgresql.org/docs/9.1/static/indexes-ordering.html

-- CREATE INDEX CONCURRENTLY browse_entry_sort_value_idx_desc
--     ON metabib.browse_entry USING BTREE (sort_value DESC);

CREATE TYPE metabib.flat_browse_entry_appearance AS (
    browse_entry    BIGINT,
    value           TEXT,
    fields          TEXT,
    authorities     TEXT,
    sources         INT,        -- visible ones, that is
    row_number      INT,        -- internal use, sort of
    accurate        BOOL,       -- Count in sources field is accurate? Not
                                -- if we had more than a browse superpage
                                -- of records to look at.
    pivot_point     BIGINT
);


CREATE OR REPLACE FUNCTION metabib.browse_pivot(
    search_field        INT[],
    browse_term         TEXT
) RETURNS BIGINT AS $p$
DECLARE
    id                  BIGINT;
BEGIN
    SELECT INTO id mbe.id FROM metabib.browse_entry mbe
        JOIN metabib.browse_entry_def_map mbedm ON (
            mbedm.entry = mbe.id AND
            mbedm.def = ANY(search_field)
        )
        WHERE mbe.sort_value >= public.search_normalize(browse_term)
        ORDER BY mbe.sort_value, mbe.value LIMIT 1;

    RETURN id;
END;
$p$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.staged_browse(
    query                   TEXT,
    fields                  INT[],
    context_org             INT,
    context_locations       INT[],
    staff                   BOOL,
    browse_superpage_size   INT,
    count_up_from_zero      BOOL,   -- if false, count down from -1
    result_limit            INT,
    next_pivot_pos          INT
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    OPEN curs FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;

        -- Gather aggregate data based on the MBE row we're looking at now
        SELECT INTO all_records, result_row.authorities, result_row.fields
                ARRAY_AGG(DISTINCT source),
                ARRAY_TO_STRING(ARRAY_AGG(DISTINCT authority), $$,$$),
                ARRAY_TO_STRING(ARRAY_AGG(DISTINCT def), $$,$$)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        result_row.sources := 0;

        full_end := ARRAY_LENGTH(all_records, 1);
        superpage_size := COALESCE(browse_superpage_size, full_end);
        slice_start := 1;
        slice_end := superpage_size;

        WHILE result_row.sources = 0 AND slice_start <= full_end LOOP
            superpage_of_records := all_records[slice_start:slice_end];
            qpfts_query :=
                'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                '1::INT AS rel FROM (SELECT UNNEST(' ||
                quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

            -- We use search.query_parser_fts() for visibility testing.
            -- We're calling it once per browse-superpage worth of records
            -- out of the set of records related to a given mbe, until we've
            -- either exhausted that set of records or found at least 1
            -- visible record.

            SELECT INTO result_row.sources visible
                FROM search.query_parser_fts(
                    context_org, NULL, qpfts_query, NULL,
                    context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                ) qpfts
                WHERE qpfts.rel IS NULL;

            slice_start := slice_start + superpage_size;
            slice_end := slice_end + superpage_size;
        END LOOP;

        -- Accurate?  Well, probably.
        result_row.accurate := browse_superpage_size IS NULL OR
            browse_superpage_size >= full_end;

        IF result_row.sources > 0 THEN
            -- We've got a browse entry with visible holdings. Yay.


            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.accurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$p$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.browse(
    search_field            INT[],
    browse_term             TEXT,
    context_org             INT DEFAULT NULL,
    context_loc_group       INT DEFAULT NULL,
    staff                   BOOL DEFAULT FALSE,
    pivot_id                BIGINT DEFAULT NULL,
    result_limit            INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size value     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
    SELECT
        mbe.id,
        mbe.value,
        mbe.sort_value
    FROM metabib.browse_entry mbe
    WHERE EXISTS (SELECT 1 FROM  metabib.browse_entry_def_map mbedm WHERE
        mbedm.entry = mbe.id AND
        mbedm.def = ANY(' || quote_literal(search_field) || ')
    ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC ';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value ';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$p$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.browse(
    search_class        TEXT,
    browse_term         TEXT,
    context_org         INT DEFAULT NULL,
    context_loc_group   INT DEFAULT NULL,
    staff               BOOL DEFAULT FALSE,
    pivot_id            BIGINT DEFAULT NULL,
    result_limit        INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
BEGIN
    RETURN QUERY SELECT * FROM metabib.browse(
        (SELECT COALESCE(ARRAY_AGG(id), ARRAY[]::INT[])
            FROM config.metabib_field WHERE field_class = search_class),
        browse_term,
        context_org,
        context_loc_group,
        staff,
        pivot_id,
        result_limit
    );
END;
$p$ LANGUAGE PLPGSQL;

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[@type="nfi"]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL
WHERE
    field_class = 'series' AND name = 'seriestitle' ;

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:titleInfo[mods32:title and not (@type)]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL,
    browse_field = TRUE
WHERE
    field_class = 'title' AND name = 'proper' ;

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='alternative-nfi')]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL
WHERE
    field_class = 'title' AND name = 'alternative' ;

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='uniform-nfi')]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL
WHERE
    field_class = 'title' AND name = 'uniform' ;

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:titleInfo[mods32:title and (@type='translated-nfi')]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL
WHERE
    field_class = 'title' AND name = 'translated' ;

-- This keeps extra terms like "creator" out of browse headings.
UPDATE config.metabib_field
    SET browse_xpath = $$//*[local-name()='namePart']$$     -- vim */
    WHERE
        browse_field AND
        browse_xpath IS NULL AND
        field_class = 'author';

INSERT INTO config.org_unit_setting_type (
    name, label, grp, description, datatype
) VALUES (
    'opac.browse.pager_shortcuts',
    'Paging shortcut links for OPAC Browse',
    'opac',
    'The characters in this string, in order, will be used as shortcut links for quick paging in the OPAC browse interface. Any sequence surrounded by asterisks will be taken as a whole label, not split into individual labels at the character level, but only the first character will serve as the basis of the search.',
    'string'
);

COMMIT;

\qecho This is a browse-only reingest of your bib records. It may take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
\qecho .
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE)
    FROM biblio.record_entry;
