--Upgrade Script for 2.4.3 to 2.4.4
\set eg_version '''2.4.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.4.4', :eg_version);

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0838', :eg_version);

DELETE FROM config.metabib_field_index_norm_map
    WHERE field = 25 AND norm IN (
        SELECT id
        FROM config.index_normalizer
        WHERE func IN ('search_normalize','split_date_range')
    );


SELECT evergreen.upgrade_deps_block_check('0840', :eg_version);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.conify.config.circ_matrix_matchpoint',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.conify.config.circ_matrix_matchpoint',
        'Circulation Policy Configuration',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.conify.config.circ_matrix_matchpoint',
        'Circulation Policy Configuration Column Settings',
        'cust',
        'description'
    ),
    'string'
);


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0841', :eg_version);

ALTER TABLE config.metabib_field_ts_map DROP CONSTRAINT metabib_field_ts_map_metabib_field_fkey;
ALTER TABLE config.metabib_search_alias DROP CONSTRAINT metabib_search_alias_field_fkey;
ALTER TABLE metabib.browse_entry_def_map DROP CONSTRAINT browse_entry_def_map_def_fkey;

ALTER TABLE config.metabib_field_ts_map ADD CONSTRAINT metabib_field_ts_map_metabib_field_fkey FOREIGN KEY (metabib_field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.metabib_search_alias ADD CONSTRAINT metabib_search_alias_field_fkey FOREIGN KEY (field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.browse_entry_def_map ADD CONSTRAINT browse_entry_def_map_def_fkey FOREIGN KEY (def) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


DROP FUNCTION IF EXISTS config.modify_metabib_field(source INT, target INT);
CREATE FUNCTION config.modify_metabib_field(v_source INT, target INT) RETURNS INT AS $func$
DECLARE
    f_class TEXT;
    check_id INT;
    target_id INT;
BEGIN
    SELECT field_class INTO f_class FROM config.metabib_field WHERE id = v_source;
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    IF target IS NULL THEN
        target_id = v_source + 1000;
    ELSE
        target_id = target;
    END IF;
    SELECT id FROM config.metabib_field INTO check_id WHERE id = target_id;
    IF FOUND THEN
        RAISE NOTICE 'Cannot bump config.metabib_field.id from % to %; the target ID already exists.', v_source, target_id;
        RETURN 0;
    END IF;
    UPDATE config.metabib_field SET id = target_id WHERE id = v_source;
    EXECUTE ' UPDATE metabib.' || f_class || '_field_entry SET field = ' || target_id || ' WHERE field = ' || v_source;
    UPDATE config.metabib_field_ts_map SET metabib_field = target_id WHERE metabib_field = v_source;
    UPDATE config.metabib_field_index_norm_map SET field = target_id WHERE field = v_source;
    UPDATE search.relevance_adjustment SET field = target_id WHERE field = v_source;
    UPDATE config.metabib_search_alias SET field = target_id WHERE field = v_source;
    UPDATE metabib.browse_entry_def_map SET def = target_id WHERE def = v_source;
    RETURN 1;
END;
$func$ LANGUAGE PLPGSQL;

SELECT config.modify_metabib_field(id, NULL)
    FROM config.metabib_field
    WHERE id > 30;

SELECT SETVAL('config.metabib_field_id_seq', GREATEST(1000, (SELECT MAX(id) FROM config.metabib_field)));


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0842', :eg_version);

-- this upgrade is only for people coming from 2_3, and is a NO-OP for those on 2_4 or later
ALTER TABLE config.metabib_field_ts_map DROP CONSTRAINT metabib_field_ts_map_metabib_field_fkey;

ALTER TABLE config.metabib_field_ts_map ADD CONSTRAINT metabib_field_ts_map_metabib_field_fkey FOREIGN KEY (metabib_field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


SELECT evergreen.upgrade_deps_block_check('0846', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT, force_add INT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;
    my $force_add = shift || 0;

    my $target_r = MARC::Record->new_from_xml( $target_xml );
    my $source_r = MARC::Record->new_from_xml( $source_xml );

    return $target_xml unless ($target_r && $source_r);

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
                }
            }
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}{sf}} ) {
            for my $from_field ($source_r->field( $f )) {
                my @tos = $target_r->field( $f );
                if (!@tos) {
                    next if (exists($fields{$f}{match}) and !$force_add);
                    my @new_fields = map { $_->clone } $source_r->field( $f );
                    $target_r->insert_fields_ordered( @new_fields );
                } else {
                    for my $to_field (@tos) {
                        if (exists($fields{$f}{match})) {
                            next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
                        }
                        for my $old_sf ($from_field->subfields) {
                            $to_field->add_subfields( @$old_sf ) if grep(/$$old_sf[0]/,@{$fields{$f}{sf}});
                        }
                    }
                }
            }
        } else {
            my @new_fields = map { $_->clone } $source_r->field( $f );
            $target_r->insert_fields_ordered( @new_fields );
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;



SELECT evergreen.upgrade_deps_block_check('0847', :eg_version);

CREATE OR REPLACE FUNCTION authority.generate_overlay_template (source_xml TEXT) RETURNS TEXT AS $f$
DECLARE
    cset                INT;
    main_entry          authority.control_set_authority_field%ROWTYPE;
    bib_field           authority.control_set_bib_field%ROWTYPE;
    auth_id             INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', source_xml)::INT;
    tmp_data            XML;
    replace_data        XML[] DEFAULT '{}'::XML[];
    replace_rules       TEXT[] DEFAULT '{}'::TEXT[];
    auth_field          XML[];
    auth_i1             TEXT;
    auth_i2             TEXT;
BEGIN
    IF auth_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Default to the LoC controll set
    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    -- if none, make a best guess
    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN (
                    SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marc::XML)::TEXT[])
                      FROM  authority.record_entry
                      WHERE id = auth_id
                )
          LIMIT 1;
    END IF;

    -- if STILL none, no-op change
    IF cset IS NULL THEN
        RETURN XMLELEMENT(
            name record,
            XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
            XMLELEMENT( name leader, '00881nam a2200193   4500'),
            XMLELEMENT(
                name datafield,
                XMLATTRIBUTES( '905' AS tag, ' ' AS ind1, ' ' AS ind2),
                XMLELEMENT(
                                      name subfield,
                    XMLATTRIBUTES('d' AS code),
                    '901c'
                )
            )
        )::TEXT;
    END IF;

    FOR main_entry IN SELECT * FROM authority.control_set_authority_field acsaf WHERE acsaf.control_set = cset AND acsaf.main_entry IS NULL LOOP
        auth_field := XPATH('//*[@tag="'||main_entry.tag||'"][1]',source_xml::XML);
        auth_i1 = (XPATH('@ind1',auth_field[1]))[1];
        auth_i2 = (XPATH('@ind2',auth_field[1]))[1];
        IF ARRAY_LENGTH(auth_field,1) > 0 THEN
            FOR bib_field IN SELECT * FROM authority.control_set_bib_field WHERE authority_field = main_entry.id LOOP
                SELECT XMLELEMENT( -- XMLAGG avoids magical <element> creation, but requires unnest subquery
                    name datafield,
                    XMLATTRIBUTES(bib_field.tag AS tag, auth_i1 AS ind1, auth_i2 AS ind2),
                    XMLAGG(UNNEST)
                ) INTO tmp_data FROM UNNEST(XPATH('//*[local-name()="subfield"]', auth_field[1]));
                replace_data := replace_data || tmp_data;
                replace_rules := replace_rules || ( bib_field.tag || main_entry.sf_list || E'[0~\\)' || auth_id || '$]' );
                tmp_data = NULL;
            END LOOP;
            EXIT;
        END IF;
    END LOOP;

    SELECT XMLAGG(UNNEST) INTO tmp_data FROM UNNEST(replace_data);

    RETURN XMLELEMENT(
        name record,
        XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
        XMLELEMENT( name leader, '00881nam a2200193   4500'),
        tmp_data,
        XMLELEMENT(
            name datafield,
                         XMLATTRIBUTES( '905' AS tag, ' ' AS ind1, ' ' AS ind2),
            XMLELEMENT(
                name subfield,
                XMLATTRIBUTES('r' AS code),
                ARRAY_TO_STRING(replace_rules,',')
            )
        )
    )::TEXT;
END;
$f$ STABLE LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0848', :eg_version);

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT, no_thesaurus BOOL ) RETURNS TEXT AS $func$
DECLARE
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    sf_node         TEXT;
    tag_node        TEXT;
    thes_code       TEXT;
    cset            INT;
    heading_text    TEXT;
    tmp_text        TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT;
BEGIN
    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN ( SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    thes_code := vandelay.marc21_extract_fixed_field(marcxml,'Subj');
    IF thes_code IS NULL THEN
        thes_code := '|';
    ELSIF thes_code = 'z' THEN
        thes_code := COALESCE( oils_xpath_string('//*[@tag="040"]/*[@code="f"][1]', marcxml), '' );
    END IF;

    heading_text := '';
    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset AND main_entry IS NULL LOOP
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        first_sf := TRUE;

        FOR tag_node IN SELECT unnest(oils_xpath('//*[@tag="'||tag_used||'"]',marcxml)) LOOP
            FOR sf_node IN SELECT unnest(oils_xpath('//*[contains("'||acsaf.sf_list||'",@code)]',tag_node)) LOOP

                tmp_text := oils_xpath_string('.', sf_node);
                sf := oils_xpath_string('./@code', sf_node);

                IF first_sf AND tmp_text IS NOT NULL AND nfi_used IS NOT NULL THEN

                    tmp_text := SUBSTRING(
                        tmp_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('./@ind'||nfi_used, tag_node),
                                    $$\D+$$,
                                    '',
                                    'g'
                                ),
                                ''
                            )::INT,
                            0
                        ) + 1
                    );

                END IF;

                first_sf := FALSE;

                IF tmp_text IS NOT NULL AND tmp_text <> '' THEN
                    heading_text := heading_text || E'\u2021' || sf || ' ' || tmp_text;
                END IF;
            END LOOP;

            EXIT WHEN heading_text <> '';
        END LOOP;

        EXIT WHEN heading_text <> '';
    END LOOP;

    IF heading_text <> '' THEN
        IF no_thesaurus IS TRUE THEN
            heading_text := tag_used || ' ' || public.naco_normalize(heading_text);
        ELSE
            heading_text := tag_used || '_' || COALESCE(nfi_used,'-') || '_' || thes_code || ' ' || public.naco_normalize(heading_text);
        END IF;
    ELSE
        heading_text := 'NOHEADING_' || thes_code || ' ' || MD5(marcxml);
    END IF;

    RETURN heading_text;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml)::INT;
BEGIN

    res.record := auth_id;

    SELECT  control_set INTO cset
      FROM  authority.control_set_authority_field
      WHERE tag IN ( SELECT UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]) )
      LIMIT 1;

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP

        res.atag := acsaf.id;
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;

        FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)) LOOP

            heading_text := public.naco_normalize(
                COALESCE(
                    oils_xpath_string('//*[contains("'||acsaf.sf_list||'",@code)]',tmp_xml::TEXT, ' '),
                    ''
                )
            );

            IF nfi_used IS NOT NULL THEN

                sort_text := SUBSTRING(
                    heading_text FROM
                    COALESCE(
                        NULLIF(
                            REGEXP_REPLACE(
                                oils_xpath_string('./@ind'||nfi_used, tmp_xml::TEXT),
                                $$\D+$$,
                                '',
                                'g'
                            ),
                            ''
                        )::INT,
                        0
                    ) + 1
                );

            ELSE
                sort_text := heading_text;
            END IF;

            IF heading_text IS NOT NULL AND heading_text <> '' THEN
                res.value := heading_text;
                res.sort_value := sort_text;
                RETURN NEXT res;
            END IF;

        END LOOP;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;


COMMIT;

\qecho If your site's bibcn searches are affected the issue addressed in 0838
\qecho you may wish to reingest your bib records now.  It's probably not worth
\qecho it for many sites.


