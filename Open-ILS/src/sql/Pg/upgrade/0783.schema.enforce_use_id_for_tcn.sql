-- Evergreen DB patch 0783.schema.enforce_use_id_for_tcn.sql
--
-- Sets the TCN value in the biblio.record_entry row to bib ID,
-- if the appropriate setting is in place
--
BEGIN;

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
