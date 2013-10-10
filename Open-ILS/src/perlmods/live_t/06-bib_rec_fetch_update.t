#!perl

use Test::More tests => 6;

diag("Fetches and updates a bib records MARC data");

use strict; use warnings;

use MARC::Record;                                                              
use MARC::Field;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::Normalize qw/clean_marc/;
my $script = OpenILS::Utils::TestUtils->new();

my $test_record = 1;
my $test_title = 'La canzone italiana del Novecento :';
my $test_note = "Live Test Note";

# we need auth to access protected APIs
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');
 
my $ses = $script->session('open-ils.cstore');
my $req = $ses->request(
    'open-ils.cstore.direct.biblio.record_entry.retrieve', 
    $test_record);

my $bre;
if (my $resp = $req->recv) {
    if ($bre = $resp->content) {
        is(
            ref $bre,
            'Fieldmapper::biblio::record_entry',
            'open-ils.cstore.direct.biblio.record_entry.retrieve '.
                'returned a bre object'
        );
    }
}

my $marc = MARC::Record->new_from_xml($bre->marc);
is(
    $marc->subfield('245', 'a'),
    $test_title,
    'subfield(245, a) returned expected value'
);

my $field = MARC::Field->new('999','','','a' => $test_note);
$marc->append_fields($field);

is(
    $marc->subfield('999', 'a'),
    $test_note, 
    'subfield(999, a) has correct note'
);

$req = $script->session('open-ils.cat')->request(
    'open-ils.cat.biblio.record.xml.update',
    $authtoken, $bre->id, clean_marc($marc->as_xml));

if (my $resp = $req->recv) {
    if ($bre = $resp->content) {
        is(
            ref $bre,
            'Fieldmapper::biblio::record_entry',
            'open-ils.cat.biblio.record.xml.update returned a bre object'
        );

        my $marc = MARC::Record->new_from_xml($bre->marc);
        
        is(
            $marc->subfield('999', 'a'),
            $test_note, 
            'Updated MARC subfield(999, a) has correct note'
        );
    }
}

