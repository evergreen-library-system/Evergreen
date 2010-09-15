BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0400'); -- dbs

CREATE OR REPLACE FUNCTION authority.normalize_heading( TEXT ) RETURNS TEXT AS $func$
    use strict;
    use warnings;
    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF8');

    my $xml = shift();
    my $r = MARC::Record->new_from_xml( $xml );
    return undef unless ($r);

    # From http://www.loc.gov/standards/sourcelist/subject.html
    my $thes_code_map = {
        a => 'lcsh',
        b => 'lcshac',
        c => 'mesh',
        d => 'nal',
        k => 'cash',
        n => 'notapplicable',
        r => 'aat',
        s => 'sears',
        v => 'rvm',
    };

    # Default to "No attempt to code" if the leader is horribly broken
    my $thes_char = substr($r->field('008')->data(), 11, 1) || '|';

    my $thes_code = 'UNDEFINED';

    if ($thes_char eq 'z') {
        # Grab the 040 $f per http://www.loc.gov/marc/authority/ad040.html
        $thes_code = $r->subfield('040', 'f') || 'UNDEFINED';
    } elsif ($thes_code_map->{$thes_char}) {
        $thes_code = $thes_code_map->{$thes_char};
    }

    my $head = $r->field('1..');
    my $auth_txt = '';
    foreach my $sf ($head->subfields()) {
        $auth_txt .= $sf->[1];
    }

    
    # Perhaps better to parameterize the spi and pass as a parameter
    $auth_txt =~ s/'//go;
    my $result = spi_exec_query("SELECT public.naco_normalize('$auth_txt') AS norm_text");
    my $norm_txt = $result->{rows}[0]->{norm_text};

    return $head->tag() . "_" . $thes_code . " " . $norm_txt;
$func$ LANGUAGE 'plperlu' IMMUTABLE;

COMMENT ON FUNCTION authority.normalize_heading( TEXT ) IS $$
/**
* Extract the authority heading, thesaurus, and NACO-normalized values
* from an authority record. The primary purpose is to build a unique
* index to defend against duplicated authority records from the same
* thesaurus.
*/
$$;

COMMIT;

-- Do this outside of a transaction to avoid failure if duplicate
-- authority heading / thesaurus / heading text entries already
-- exist in the database:
CREATE UNIQUE INDEX unique_by_heading_and_thesaurus
    ON authority.record_entry (authority.normalize_heading(marc))
    WHERE deleted IS FALSE or deleted = FALSE
;

-- If the unique index fails, uncomment the following to create
-- a regular index that will help find the duplicates in a hurry:
--CREATE INDEX by_heading_and_thesaurus
--    ON authority.record_entry (authority.normalize_heading(marc))
--    WHERE deleted IS FALSE or deleted = FALSE
--;

-- Then find the duplicates like so to get an idea of how much
-- pain you're looking at to clean things up:
--SELECT id, authority.normalize_heading(marc)
--    FROM authority.record_entry
--    WHERE authority.normalize_heading(marc) IN (
--        SELECT authority.normalize_heading(marc)
--        FROM authority.record_entry
--        GROUP BY authority.normalize_heading(marc)
--        HAVING COUNT(*) > 1
--    )
--;

-- Once you have removed the duplicates and the CREATE UNIQUE INDEX
-- statement succeeds, drop the temporary index to avoid unnecessary
-- duplication:
-- DROP INDEX authority.by_heading_and_thesaurus;
