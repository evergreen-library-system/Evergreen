/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008  Equinox Software, Inc.
 * Copyright (C) 2010  Laurentian University
 * Mike Rylander <miker@esilibrary.com> 
 * Dan Scott <dscott@laurentian.ca>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

DROP SCHEMA IF EXISTS authority CASCADE;

BEGIN;
CREATE SCHEMA authority;

CREATE TABLE authority.control_set (
    id          SERIAL  PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT                     -- i18n
);

CREATE TABLE authority.control_set_authority_field (
    id          SERIAL  PRIMARY KEY,
    control_set INT     NOT NULL REFERENCES authority.control_set (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    tag         CHAR(3) NOT NULL,
    name        TEXT    NOT NULL, -- i18n
    description TEXT              -- i18n
);

CREATE TABLE authority.control_set_bib_field (
    id              SERIAL  PRIMARY KEY,
    authority_field INT     NOT NULL REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    tag             CHAR(3) NOT NULL,
    name            TEXT    NOT NULL, -- i18n
    description     TEXT              -- i18n
);

CREATE TABLE authority.thesaurus (
    code        TEXT    PRIMARY KEY,     -- MARC21 thesaurus code
    control_set INT     NOT NULL REFERENCES authority.control_set (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT                     -- i18n
);

CREATE TABLE authority.record_entry (
    id              BIGSERIAL    PRIMARY KEY,
    create_date     TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    edit_date       TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    creator         INT     NOT NULL DEFAULT 1,
    editor          INT     NOT NULL DEFAULT 1,
    active          BOOL    NOT NULL DEFAULT TRUE,
    deleted         BOOL    NOT NULL DEFAULT FALSE,
    source          INT,
    control_set     INT     REFERENCES authority.control_set (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    marc            TEXT    NOT NULL,
    last_xact_id    TEXT    NOT NULL,
    owner           INT
);
CREATE INDEX authority_record_entry_creator_idx ON authority.record_entry ( creator );
CREATE INDEX authority_record_entry_editor_idx ON authority.record_entry ( editor );
CREATE INDEX authority_record_deleted_idx ON authority.record_entry(deleted) WHERE deleted IS FALSE OR deleted = false;
CREATE TRIGGER a_marcxml_is_well_formed BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.check_marcxml_well_formed();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_control_numbers();
CREATE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id);

CREATE TABLE authority.bib_linking (
    id          BIGSERIAL   PRIMARY KEY,
    bib         BIGINT      NOT NULL REFERENCES biblio.record_entry (id),
    authority   BIGINT      NOT NULL REFERENCES authority.record_entry (id)
);
CREATE INDEX authority_bl_bib_idx ON authority.bib_linking ( bib );
CREATE UNIQUE INDEX authority_bl_bib_authority_once_idx ON authority.bib_linking ( authority, bib );

CREATE TABLE authority.record_note (
    id          BIGSERIAL   PRIMARY KEY,
    record      BIGINT      NOT NULL REFERENCES authority.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
    value       TEXT        NOT NULL,
    creator     INT         NOT NULL DEFAULT 1,
    editor      INT         NOT NULL DEFAULT 1,
    create_date TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now(),
    edit_date   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT now()
);
CREATE INDEX authority_record_note_record_idx ON authority.record_note ( record );
CREATE INDEX authority_record_note_creator_idx ON authority.record_note ( creator );
CREATE INDEX authority_record_note_editor_idx ON authority.record_note ( editor );

CREATE TABLE authority.rec_descriptor (
    id              BIGSERIAL PRIMARY KEY,
    record          BIGINT,
    record_status   TEXT,
    char_encoding   TEXT,
    thesaurus       TEXT
);
CREATE INDEX authority_rec_descriptor_record_idx ON authority.rec_descriptor (record);

CREATE TABLE authority.full_rec (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL,
    tag             CHAR(3)     NOT NULL,
    ind1            TEXT,
    ind2            TEXT,
    subfield        TEXT,
    value           TEXT        NOT NULL,
    index_vector    tsvector    NOT NULL
);
CREATE INDEX authority_full_rec_record_idx ON authority.full_rec (record);
CREATE INDEX authority_full_rec_tag_subfield_idx ON authority.full_rec (tag, subfield);
CREATE INDEX authority_full_rec_tag_part_idx ON authority.full_rec (SUBSTRING(tag FROM 2));
CREATE INDEX authority_full_rec_subfield_a_idx ON authority.full_rec (value) WHERE subfield = 'a';
CREATE TRIGGER authority_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.full_rec
    FOR EACH ROW EXECUTE PROCEDURE tsearch2(index_vector, value);

CREATE INDEX authority_full_rec_index_vector_idx ON authority.full_rec USING GIST (index_vector);
/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (value text_pattern_ops);

CREATE OR REPLACE VIEW authority.tracing_links AS
    SELECT  main.record AS record,
            main.id AS main_id,
            main.tag AS main_tag,
            main.value AS main_value,
            substr(link.value,1,1) AS relationship,
            substr(link.value,2,1) AS use_restriction,
            substr(link.value,3,1) AS deprecation,
            substr(link.value,4,1) AS display_restriction,
            link_value.id AS link_id,
            link_value.tag AS link_tag,
            link_value.value AS link_value
      FROM  authority.full_rec main
            JOIN authority.full_rec link
                ON (link.record = main.record
                    AND link.tag in ((main.tag::int + 400)::text, (main.tag::int + 300)::text)
                    AND link.subfield = 'w' )
            JOIN authority.full_rec link_value
                ON (link_value.record = main.record
                    AND link_value.tag = link.tag
                    AND link_value.subfield = 'a' )
      WHERE main.tag IN ('100','110','111','130','150','151','155','180','181','182','185')
            AND main.subfield = 'a';

-- Function to generate an ephemeral overlay template from an authority record
CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT, BIGINT ) RETURNS TEXT AS $func$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;

    MARC::Charset->assume_unicode(1);

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return undef unless ($r);

    my $id = shift() || $r->subfield( '901' => 'c' );
    $id =~ s/^\s*(?:\([^)]+\))?\s*(.+)\s*?$/$1/;
    return undef unless ($id); # We need an ID!

    my $tmpl = MARC::Record->new();
    $tmpl->encoding( 'UTF-8' );

    my @rule_fields;
    for my $field ( $r->field( '1..' ) ) { # Get main entry fields from the authority record

        my $tag = $field->tag;
        my $i1 = $field->indicator(1);
        my $i2 = $field->indicator(2);
        my $sf = join '', map { $_->[0] } $field->subfields;
        my @data = map { @$_ } $field->subfields;

        my @replace_them;

        # Map the authority field to bib fields it can control.
        if ($tag >= 100 and $tag <= 111) {       # names
            @replace_them = map { $tag + $_ } (0, 300, 500, 600, 700);
        } elsif ($tag eq '130') {                # uniform title
            @replace_them = qw/130 240 440 730 830/;
        } elsif ($tag >= 150 and $tag <= 155) {  # subjects
            @replace_them = ($tag + 500);
        } elsif ($tag >= 180 and $tag <= 185) {  # floating subdivisions
            @replace_them = qw/100 400 600 700 800 110 410 610 710 810 111 411 611 711 811 130 240 440 730 830 650 651 655/;
        } else {
            next;
        }

        # Dummy up the bib-side data
        $tmpl->append_fields(
            map {
                MARC::Field->new( $_, $i1, $i2, @data )
            } @replace_them
        );

        # Construct some 'replace' rules
        push @rule_fields, map { $_ . $sf . '[0~\)' .$id . '$]' } @replace_them;
    }

    # Insert the replace rules into the template
    $tmpl->append_fields(
        MARC::Field->new( '905' => ' ' => ' ' => 'r' => join(',', @rule_fields ) )
    );

    $xml = $tmpl->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( BIGINT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( marc, id ) FROM authority.record_entry WHERE id = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( $1, NULL );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.merge_records ( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    bib_id        INT := 0;
    bib_rec       biblio.record_entry%ROWTYPE;
    auth_link     authority.bib_linking%ROWTYPE;
    ingest_same   boolean;
BEGIN

    -- Defining our terms:
    -- "target record" = the record that will survive the merge
    -- "source record" = the record that is sacrifing its existence and being
    --   replaced by the target record

    -- 1. Update all bib records with the ID from target_record in their $0
    FOR bib_rec IN
            SELECT  bre.*
              FROM  biblio.record_entry bre 
                    JOIN authority.bib_linking abl ON abl.bib = bre.id
              WHERE abl.authority = source_record
        LOOP

        UPDATE  biblio.record_entry
          SET   marc = REGEXP_REPLACE(
                    marc,
                    E'(<subfield\\s+code="0"\\s*>[^<]*?\\))' || source_record || '<',
                    E'\\1' || target_record || '<',
                    'g'
                )
          WHERE id = bib_rec.id;

          moved_objects := moved_objects + 1;
    END LOOP;

    -- 2. Grab the current value of reingest on same MARC flag
    SELECT  enabled INTO ingest_same
      FROM  config.internal_flag
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 3. Temporarily set reingest on same to TRUE
    UPDATE  config.internal_flag
      SET   enabled = TRUE
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 4. Make a harmless update to target_record to trigger auto-update
    --    in linked bibliographic records
    UPDATE  authority.record_entry
      SET   deleted = FALSE
      WHERE id = target_record;

    -- 5. "Delete" source_record
    DELETE FROM authority.record_entry WHERE id = source_record;

    -- 6. Set "reingest on same MARC" flag back to initial value
    UPDATE  config.internal_flag
      SET   enabled = ingest_same
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

COMMIT;
