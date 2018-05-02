BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

CREATE OR REPLACE FUNCTION biblio.set_record_status_in_leader() RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::Field;
use MARC::File::XML (BinaryEncoding => 'utf8');
use Unicode::Normalize;

my $old_marc = MARC::Record->new_from_xml($_TD->{new}{marc});
my $old_leader = $old_marc->leader();
my $old_status = substr($old_leader,5,1);

my $status;
if ($_TD->{event} eq 'INSERT') {$status = 'n';}
elsif ($_TD->{event} eq 'UPDATE' && $_TD->{new}{deleted} eq 't') {$status = 'd';}
elsif ($_TD->{event} eq 'UPDATE' && $_TD->{new}{deleted} eq 'f') {$status = 'c';}

if ($old_status ne $status) {
    my $marc = MARC::Record->new_from_xml($_TD->{new}{marc});
    my $leader = $marc->leader();
    substr($leader,5,1) = $status;
    $marc->leader($leader);
    my $marc_xml = $marc->as_xml_record();
    $marc_xml = NFC($marc_xml);  
    $_TD->{new}{marc} = $marc_xml;
} 

return "MODIFY";

$func$ LANGUAGE PLPERLU;

CREATE TRIGGER set_record_status_in_leader BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.set_record_status_in_leader();

COMMIT;
