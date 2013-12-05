--Upgrade Script for 2.3.11 to 2.3.12
\set eg_version '''2.3.12'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.3.12', :eg_version);

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0838', :eg_version);

DELETE FROM config.metabib_field_index_norm_map
    WHERE field = 25 AND norm IN (
        SELECT id
        FROM config.index_normalizer
        WHERE func IN ('search_normalize','split_date_range')
    );

\qecho If your site's bibcn searches are affected by this issue, you may wish
\qecho to reingest your bib records now.  It's probably not worth it for many
\qecho sites.


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

ALTER TABLE config.metabib_search_alias DROP CONSTRAINT metabib_search_alias_field_fkey;
ALTER TABLE metabib.browse_entry_def_map DROP CONSTRAINT browse_entry_def_map_def_fkey;

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


COMMIT;
