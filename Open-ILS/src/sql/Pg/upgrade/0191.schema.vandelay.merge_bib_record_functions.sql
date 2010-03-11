
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0191'); -- miker

ALTER TABLE vandelay.merge_profile DROP CONSTRAINT add_replace_strip_or_preserve;
ALTER TABLE vandelay.merge_profile ADD CONSTRAINT add_replace_strip_or_preserve CHECK ((preserve_spec IS NOT NULL OR replace_spec IS NOT NULL) OR (preserve_spec IS NULL AND replace_spec IS NULL));

CREATE OR REPLACE FUNCTION vandelay.match_bib_record ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr        RECORD;
    eg_rec      RECORD;
    id_value    TEXT;
    exact_id    BIGINT;
BEGIN

    SELECT * INTO attr FROM vandelay.bib_attr_definition WHERE xpath = '//*[@tag="901"]/*[@code="c"]' ORDER BY id LIMIT 1;

    IF attr IS NOT NULL AND attr.id IS NOT NULL THEN
        id_value := extract_marc_field('vandelay.queued_bib_record', NEW.id, attr.xpath, attr.remove);

        IF id_value IS NOT NULL AND id_value <> '' AND id_value ~ $r$^\d+$$r$ THEN
            SELECT id INTO exact_id FROM biblio.record_entry WHERE id = id_value::BIGINT AND NOT deleted;
            IF exact_id IS NOT NULL THEN
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, exact_id);
            END IF;
        END IF;
    END IF;

    IF exact_id IS NULL THEN
        FOR attr IN SELECT a.* FROM vandelay.queued_bib_record_attr a JOIN vandelay.bib_attr_definition d ON (d.id = a.field) WHERE record = NEW.id AND d.ident IS TRUE LOOP

            -- All numbers? check for an id match
            IF (attr.attr_value ~ $r$^\d+$$r$) THEN
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE id = attr.attr_value::BIGINT AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- Looks like an ISBN? check for an isbn match
            IF (attr.attr_value ~* $r$^[0-9x]+$$r$ AND character_length(attr.attr_value) IN (10,13)) THEN
                FOR eg_rec IN EXECUTE $$SELECT * FROM metabib.full_rec fr WHERE fr.value LIKE LOWER('$$ || attr.attr_value || $$%') AND fr.tag = '020' AND fr.subfield = 'a'$$ LOOP
                    PERFORM id FROM biblio.record_entry WHERE id = eg_rec.record AND deleted IS FALSE;
                    IF FOUND THEN
                        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('isbn', attr.id, NEW.id, eg_rec.record);
                    END IF;
                END LOOP;

                -- subcheck for isbn-as-tcn
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = 'i' || attr.attr_value AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- check for an OCLC tcn_value match
            IF (attr.attr_value ~ $r$^o\d+$$r$) THEN
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = regexp_replace(attr.attr_value,'^o','ocm') AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- check for a direct tcn_value match
            FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = attr.attr_value AND deleted IS FALSE LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
            END LOOP;

            -- check for a direct item barcode match
            FOR eg_rec IN
                    SELECT  DISTINCT b.*
                      FROM  biblio.record_entry b
                            JOIN asset.call_number cn ON (cn.record = b.id)
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cp.barcode = attr.attr_value AND cp.deleted IS FALSE
            LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
            END LOOP;

        END LOOP;
    END IF;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML;

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;
    $field_spec =~ s/\s+//sg;

    my $target_r = MARC::Record->new_from_xml( $target_xml );
    my $source_r = MARC::Record->new_from_xml( $source_xml );

    return $target_xml unless ($target_r && $source_r);

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        if ($f =~ /^(.{3})(.*)$/) {
            $fields{$1} = [ split('', $2) ];
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}} ) {
            for my $from_field ($source_r->field( $f )) {
                for my $to_field ($target_r->field( $f )) {
                    my @new_sf = map { ($_ => $from_field->subfield($_)) } @{$fields{$f}};
                    $to_field->add_subfields( @new_sf );
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

CREATE OR REPLACE FUNCTION vandelay.strip_field ( xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML;

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    $field_spec =~ s/\s+//sg;

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        if ($f =~ /^(.{3})(.*)$/) {
            $fields{$1} = [ split('', $2) ];
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}} ) {
            $_->delete_subfield(code => $fields{$f}) for ($r->field( $f ));
        } else {
            $r->delete_field( $_ ) for ( $r->field( $f ) );
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.replace_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( vandelay.strip_field( $1, $3), $2, $3 );
$_$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml ( target_xml TEXT, source_xml TEXT, add_rule TEXT, replace_preserve_rule TEXT, strip_rule TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.replace_field( vandelay.add_field( vandelay.strip_field( $1, $5) , $2, $3 ), $2, $4);
$_$ LANGUAGE SQL;

CREATE TYPE vandelay.compile_profile AS (add_rule TEXT, replace_rule TEXT, preserve_rule TEXT, strip_rule TEXT);
CREATE OR REPLACE FUNCTION vandelay.compile_profile ( incoming_xml TEXT ) RETURNS vandelay.compile_profile AS $_$
DECLARE
    output              vandelay.compile_profile%ROWTYPE;
    profile             vandelay.merge_profile%ROWTYPE;
    profile_tmpl        TEXT;
    profile_tmpl_owner  TEXT;
    add_rule            TEXT := '';
    strip_rule          TEXT := '';
    replace_rule        TEXT := '';
    preserve_rule       TEXT := '';

BEGIN

    profile_tmpl := (oils_xpath('//*[@tag="905"]/*[@code="t"]/text()',incoming_xml))[1];
    profile_tmpl_owner := (oils_xpath('//*[@tag="905"]/*[@code="o"]/text()',incoming_xml))[1];

    IF profile_tmpl IS NOT NULL AND profile_tmpl <> '' AND profile_tmpl_owner IS NOT NULL AND profile_tmpl_owner <> '' THEN
        SELECT  p.* INTO profile
          FROM  vandelay.merge_profile p
                JOIN actor.org_unit u ON (u.id = p.owner)
          WHERE p.name = profile_tmpl
                AND u.shortname = profile_tmpl_owner;

        IF profile.id IS NOT NULL THEN
            add_rule := add_rule || COALESCE(profile.add_spec,'');
            strip_rule := strip_rule || COALESCE(profile.strip_spec,'');
            replace_rule := replace_rule || COALESCE(profile.replace_spec,'');
            preserve_rule := preserve_rule || COALESCE(profile.preserve_spec,'');
        END IF;
    END IF;

    add_rule := add_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="a"]/text()',incoming_xml),''),'');
    strip_rule := strip_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="d"]/text()',incoming_xml),''),'');
    replace_rule := replace_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="r"]/text()',incoming_xml),''),'');
    preserve_rule := preserve_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="p"]/text()',incoming_xml),''),'');

    output.add_rule := add_rule;
    output.replace_rule := replace_rule;
    output.strip_rule := strip_rule;
    output.preserve_rule := preserve_rule;

    RETURN output;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    eg_id           BIGINT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN
    SELECT COUNT(*) INTO match_count FROM vandelay.bib_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.bib_match m
      WHERE m.queued_record = import_id
      LIMIT 1;

    SELECT  b.marc INTO eg_marc
      FROM  biblio.record_entry b
            JOIN vandelay.bib_match m ON (m.eg_record = b.id AND m.queued_record = import_id)
      LIMIT 1;

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        RETURN FALSE;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := BTRIM( dyn_profile.add_rule || ',' || COALESCE(merge_profile.add_spec,''), ',');
            dyn_profile.strip_rule := BTRIM( dyn_profile.strip_rule || ',' || COALESCE(merge_profile.strip_spec,''), ',');
            dyn_profile.replace_rule := BTRIM( dyn_profile.replace_rule || ',' || COALESCE(merge_profile.replace_spec,''), ',');
            dyn_profile.preserve_rule := BTRIM( dyn_profile.preserve_rule || ',' || COALESCE(merge_profile.preserve_spec,''), ',');
        END IF;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF FOUND THEN
        UPDATE  vandelay.queued_bib_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;
        RETURN TRUE;
    END IF;

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue ( queue_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_bib_record%ROWTYPE;
    success         BOOL;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_bib_record WHERE queue = queue_id AND import_time IS NULL LOOP
        success := vandelay.auto_overlay_bib_record( queued_record.id, merge_profile_id );

        IF success THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue ( queue_id BIGINT ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM vandelay.auto_overlay_bib_queue( $1, NULL );
$$ LANGUAGE SQL;

COMMIT;

