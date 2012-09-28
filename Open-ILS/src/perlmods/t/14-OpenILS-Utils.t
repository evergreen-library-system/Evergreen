#!perl -T

use Test::More tests => 29;

use_ok( 'OpenILS::Utils::Configure' );
use_ok( 'OpenILS::Utils::Cronscript' );
use_ok( 'OpenILS::Utils::CStoreEditor' );
use_ok( 'OpenILS::Utils::Editor' );
use_ok( 'OpenILS::Utils::Fieldmapper' );
use_ok( 'OpenILS::Utils::ISBN' );
use_ok( 'OpenILS::Utils::Lockfile' );
use_ok( 'OpenILS::Utils::MFHDParser' );
use_ok( 'OpenILS::Utils::MFHD' );
use_ok( 'OpenILS::Utils::ModsParser' );
use_ok( 'OpenILS::Utils::Normalize' );
use_ok( 'OpenILS::Utils::OfflineStore' );
use_ok( 'OpenILS::Utils::Penalty' );
use_ok( 'OpenILS::Utils::PermitHold' );
use_ok( 'OpenILS::Utils::RemoteAccount' );
use_ok( 'OpenILS::Utils::ScriptRunner' );
use_ok( 'OpenILS::Utils::SpiderMonkey' );
use_ok( 'OpenILS::Utils::ZClient' );
use_ok( 'OpenILS::Utils::EDIReader' );

# LP 800269 - Test MFHD holdings for records that only contain a caption field
my $co_marc = MARC::Record->new();
$co_marc->append_fields(
    MARC::Field->new('853','','',
        '8' => '1',
        'a' => 'v.',
        'b' => '[no.]',
    )
);
my $co_mfhd = MFHD->new($co_marc);

my @comp_holdings = $co_mfhd->get_compressed_holdings($co_mfhd->field('853'));
is(@comp_holdings, 0, "Compressed holdings for an MFHD record that only has a caption");

my @decomp_holdings = $co_mfhd->get_decompressed_holdings($co_mfhd->field('853'));
is(@decomp_holdings, 0, "Decompressed holdings for an MFHD record that only has a caption");

my $apostring = OpenILS::Utils::Normalize::naco_normalize("it's time");
is($apostring, "its time", "naco_normalize: strip apostrophes");

my $apos = OpenILS::Utils::Normalize::search_normalize("it's time");
is($apos, "it s time", "search_normalize: replace apostrophes with space");

my $raw_marcxml = <<RAWMARC;
<?xml version="1.0" encoding="utf-8"?>
<record>
  <leader>01614nmm a22003975u 4500</leader>
  <controlfield tag="001">978-0-387-35767-6</controlfield>
  <controlfield tag="003">Springer</controlfield>
  <controlfield tag="005">20071022150035.8</controlfield>
  <controlfield tag="007">cr nn 008mamaa</controlfield>
  <controlfield tag="008">071022s2008    xx         j        eng d</controlfield>
  <datafield tag="020" ind1=" " ind2=" ">
    <subfield code="a">9780387685748</subfield>
  </datafield>
  <datafield tag="100" ind1="1" ind2=" ">
    <subfield code="a">Neteler, Markus.</subfield>
  </datafield>
  <datafield tag="245" ind1="1" ind2="0">
    <subfield code="a">Open Source GIS</subfield>
    <subfield code="h">[electronic resource] :</subfield>
    <subfield code="b">A GRASS GIS Approach /</subfield>
    <subfield code="c">edited by Markus Neteler, Helena Mitasova.</subfield>
  </datafield>
  <datafield tag="250" ind1=" " ind2=" ">
    <subfield code="a">Third Edition.</subfield>
  </datafield>
  <datafield tag="260" ind1=" " ind2=" ">
    <subfield code="a">Boston, MA :</subfield>
    <subfield code="b">Springer Science+Business Media, LLC,</subfield>
    <subfield code="c">2008.</subfield>
  </datafield>
</record>
RAWMARC
my $exp_xml = '<record><leader>01614nmm a22003975u 4500</leader><controlfield tag="001">978-0-387-35767-6</controlfield><controlfield tag="003">Springer</controlfield><controlfield tag="005">20071022150035.8</controlfield><controlfield tag="007">cr nn 008mamaa</controlfield><controlfield tag="008">071022s2008    xx         j        eng d</controlfield><datafield tag="020" ind1=" " ind2=" "><subfield code="a">9780387685748</subfield></datafield><datafield tag="100" ind1="1" ind2=" "><subfield code="a">Neteler, Markus.</subfield></datafield><datafield tag="245" ind1="1" ind2="0"><subfield code="a">Open Source GIS</subfield><subfield code="h">[electronic resource] :</subfield><subfield code="b">A GRASS GIS Approach /</subfield><subfield code="c">edited by Markus Neteler, Helena Mitasova.</subfield></datafield><datafield tag="250" ind1=" " ind2=" "><subfield code="a">Third Edition.</subfield></datafield><datafield tag="260" ind1=" " ind2=" "><subfield code="a">Boston, MA :</subfield><subfield code="b">Springer Science+Business Media, LLC,</subfield><subfield code="c">2008.</subfield></datafield></record>';
my $clean_xml = OpenILS::Utils::Normalize::clean_marc($raw_marcxml);
is($clean_xml, $exp_xml, "clean_marc: header and space normalization");

is(OpenILS::Utils::Normalize::clean_marc('èöçÇÈÀ'), '&#xE8;&#xF6;&#xE7;&#xC7;&#xC8;&#xC0;', 'clean_marc: diacritics');

my $edi_invoice = "UNA:+.? 'UNB+UNOC:3+1556150:31B+123EVER:31B+120926:1621+4'UNH+11+INVOIC:D:96A:UN'BGM+380+5TST084026+9'DTM+137:20120924:102'RFF+ON:24'NAD+BY+123EVER 0001::91'NAD+SU+1691503::31B'CUX+2:USD:4'LIN+1++9780446360272'QTY+47:5'MOA+146:4.5:USD:10'MOA+203:14.65'PRI+AAF:2.93:DI:NTP'RFF+LI:24/102'LIN+2++9780446357197'QTY+47:8'MOA+146:6.5:USD:10'MOA+203:33.84'PRI+AAF:4.23:DI:NTP'RFF+LI:24/100'UNS+S'MOA+86:66.18'ALC+C++++DL'MOA+8:2'ALC+C++++CA'MOA+131:12.3'ALC+C++++TX'MOA+8:3.39'UNT+28+11'UNH+12+INVOIC:D:96A:UN'BGM+380+5TST084027+9'DTM+137:20120924:102'RFF+ON:26'NAD+BY+123EVER 0001::91'NAD+SU+1691503::31B'CUX+2:USD:4'LIN+1++9780446360272'QTY+47:1'MOA+146:4.5:USD:10'MOA+203:4.05'PRI+AAF:4.05:DI:NTP'RFF+LI:26/106'LIN+2++9780446350105'QTY+47:3'MOA+146:6.99:USD:10'MOA+203:14.67'PRI+AAF:4.89:DI:NTP'RFF+LI:26/105'UNS+S'MOA+86:25.03'ALC+C++++DL'MOA+8:2'ALC+C++++CA'MOA+131:3'ALC+C++++TX'MOA+8:1.31'UNT+28+12'UNZ+4+4'";

my $edi_msgs = OpenILS::Utils::EDIReader->new->read($edi_invoice);

is($edi_msgs->[0]->{message_type}, 'INVOIC', 'edi reader: message type');
is($edi_msgs->[0]->{purchase_order}, '24', 'edi reader: PO number');
is($edi_msgs->[1]->{invoice_ident}, '5TST084027', 'edi reader: invoice ident');
is(scalar(@{$edi_msgs->[1]->{lineitems}}), '2', 'edi reader: lineitem count');

