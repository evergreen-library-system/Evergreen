#!perl

# FIXME: unlike the rest of the test cases here, we're /not/ enabling
# taint checks. The version of DateTime::TimeZone that ships with
# Ubuntu 14.04 LTS (Trusty) has a bug where attempting to get the
# local time zone can fail (https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=737265).
#
# It's arguable whether taint checking should be enabled at all in
# the test suite. On the one hand, it is recommended practice for
# all code that accepts external input; on the other hand, a typical
# Evergreen installation doesn't run anything setuid/setgid that
# would automatically trigger taint-checking. Ideally we would
# eat our Wheaties, but we may be looking at consuming an entire
# truckload to verify that everything would continue to work if
# we turn it on across the board.

use Test::More tests => 68;
use Test::Warn;
use DateTime::TimeZone;
use DateTime::Format::ISO8601;
use utf8;

use_ok( 'OpenILS::Utils::Configure' );
use_ok( 'OpenILS::Utils::Cronscript' );
use_ok( 'OpenILS::Utils::CStoreEditor' );
use_ok( 'OpenILS::Utils::Fieldmapper' );
use_ok( 'OpenILS::Utils::Lockfile' );
use_ok( 'OpenILS::Utils::MFHDParser' );
use_ok( 'OpenILS::Utils::MFHD' );
use_ok( 'OpenILS::Utils::ModsParser' );
use_ok( 'OpenILS::Utils::Normalize' );
use_ok( 'OpenILS::Utils::OfflineStore' );
use_ok( 'OpenILS::Utils::Penalty' );
use_ok( 'OpenILS::Utils::PermitHold' );
use_ok( 'OpenILS::Utils::RemoteAccount' );
use_ok( 'OpenILS::Utils::ZClient' );
use_ok( 'OpenILS::Utils::EDIReader' );
use_ok( 'OpenILS::Utils::HTTPClient' );
use_ok( 'OpenILS::Utils::DateTime' );

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

my @comp_holdings;
warning_like {
    @comp_holdings = $co_mfhd->get_compressed_holdings($co_mfhd->field('853'));
} [ qr/Cannot compress without pattern data, returning original holdings/ ],
    "warning when attempting to compress holdings without a pattern";

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

is(OpenILS::Application::AppUtils->entityize('èöçÇÈÀ'), '&#xE8;&#xF6;&#xE7;&#xC7;&#xC8;&#xC0;', 'entityize: diacritics NFC');
is(OpenILS::Application::AppUtils->entityize('èöçÇÈÀ', 'D'), 'e&#x300;o&#x308;c&#x327;C&#x327;E&#x300;A&#x300;', 'entityize: diacritics NFD');
is(OpenILS::Utils::Normalize::clean_marc('èöçÇÈÀ'), '&#xE8;&#xF6;&#xE7;&#xC7;&#xC8;&#xC0;', 'clean_marc: diacritics');

my $edi_invoice = "UNA:+.? 'UNB+UNOC:3+1556150:31B+123EVER:31B+120926:1621+4'UNH+11+INVOIC:D:96A:UN'BGM+380+5TST084026+9'DTM+137:20120924:102'RFF+ON:24'NAD+BY+123EVER 0001::91'NAD+SU+1691503::31B'CUX+2:USD:4'LIN+1++9780446360272'QTY+47:5'MOA+146:4.5:USD:10'MOA+203:14.65'PRI+AAF:2.93:DI:NTP'RFF+LI:24/102'LIN+2++9780446357197'QTY+47:8'MOA+146:6.5:USD:10'MOA+203:33.84'PRI+AAF:4.23:DI:NTP'RFF+LI:24/100'UNS+S'MOA+86:66.18'ALC+C++++DL'MOA+8:2'ALC+C++++CA'MOA+131:12.3'ALC+C++++TX'MOA+8:3.39'UNT+28+11'UNH+12+INVOIC:D:96A:UN'BGM+380+5TST084027+9'DTM+137:20120924:102'RFF+ON:26'NAD+BY+123EVER 0001::91'NAD+SU+1691503::31B'CUX+2:USD:4'LIN+1++9780446360272'QTY+47:1'MOA+146:4.5:USD:10'MOA+203:4.05'PRI+AAF:4.05:DI:NTP'RFF+LI:26/106'LIN+2++9780446350105'QTY+47:3'MOA+146:6.99:USD:10'MOA+203:14.67'PRI+AAF:4.89:DI:NTP'RFF+LI:26/105'UNS+S'MOA+86:25.03'ALC+C++++DL'MOA+8:2'ALC+C++++CA'MOA+131:3'ALC+C++++TX'MOA+8:1.31'UNT+28+12'UNZ+4+4'";

my $edi_msgs = OpenILS::Utils::EDIReader->new->read($edi_invoice);

is($edi_msgs->[0]->{message_type}, 'INVOIC', 'edi reader: message type');
is($edi_msgs->[0]->{purchase_order}, '24', 'edi reader: PO number');
is($edi_msgs->[1]->{invoice_ident}, '5TST084027', 'edi reader: invoice ident');
is(scalar(@{$edi_msgs->[1]->{lineitems}}), '2', 'edi reader: lineitem count');

is (OpenILS::Utils::DateTime::interval_to_seconds('1 second'), 1);
is (OpenILS::Utils::DateTime::interval_to_seconds('1 minute'), 60);
is (OpenILS::Utils::DateTime::interval_to_seconds('1 hour'), 3600);
is (OpenILS::Utils::DateTime::interval_to_seconds('1 day'), 86400);
is (OpenILS::Utils::DateTime::interval_to_seconds('1 week'), 604800);
is (OpenILS::Utils::DateTime::interval_to_seconds('1 month'), 2628000);

# With context, no DST change, with timezone
is (OpenILS::Utils::DateTime::interval_to_seconds('1 month',
    DateTime::Format::ISO8601->new->parse_datetime('2017-02-04T23:59:59-04')->set_time_zone("America/New_York")), 2419200);

# With context, with DST change, with timezone
is (OpenILS::Utils::DateTime::interval_to_seconds('1 month',
    DateTime::Format::ISO8601->new->parse_datetime('2017-02-14T23:59:59-04')->set_time_zone("America/New_York")), 2415600);

# With context, no DST change, no time zone
is (OpenILS::Utils::DateTime::interval_to_seconds('1 month',
    DateTime::Format::ISO8601->new->parse_datetime('2017-02-04T23:59:59-04')), 2419200);

# With context, with DST change, no time zone (so, not DST-aware)
is (OpenILS::Utils::DateTime::interval_to_seconds('1 month',
    DateTime::Format::ISO8601->new->parse_datetime('2017-02-14T23:59:59-04')), 2419200);

is (OpenILS::Utils::DateTime::interval_to_seconds('1 year'), 31536000);
is (OpenILS::Utils::DateTime::interval_to_seconds('1 year 1 second'), 31536001);
is (OpenILS::Utils::DateTime::interval_to_seconds('167:59:59'), 604799, 'correctly convert HHH:MM:SS intervals where hours longer than 2 digits');

sub get_offset {
    # get current timezone offset for future use
    my $offset = DateTime::TimeZone::offset_as_string(
                    DateTime::TimeZone->new( name => 'local' )->offset_for_datetime(
                        DateTime::Format::ISO8601->new()->parse_datetime('2018-09-17')
                    )
                );
    $offset =~ s/^(.\d\d)(\d\d)+/$1:$2/;
    return $offset;
}

is (OpenILS::Utils::DateTime::clean_ISO8601('20180917'), '2018-09-17T00:00:00', 'plain date converted to ISO8601 timestamp');
is (OpenILS::Utils::DateTime::clean_ISO8601('I am not a date'), 'I am not a date', 'non-date simply returned as is');
my $offset = get_offset();
is (OpenILS::Utils::DateTime::clean_ISO8601('20180917 08:31:15'), "2018-09-17T08:31:15$offset", 'time zone added to date/time');

# force timezone to specific value to avoid a spurious
# pass if this test happens to be run in UTC
$ENV{TZ} = 'EST';
is (OpenILS::Utils::DateTime::clean_ISO8601('2018-09-17T17:31:15Z'), "2018-09-17T17:31:15+00:00", 'interpret Z in timestamp correctly');

# LP#2078503 - Test extract_marc_price for handling currency symbols and non-numeric text
# Basic currency symbol extraction
is(OpenILS::Application::AppUtils->extract_marc_price('$19.95'), '19.95',
   'extract_marc_price: simple dollar amount');
is(OpenILS::Application::AppUtils->extract_marc_price('£25.50'), '25.50',
   'extract_marc_price: UK pound symbol');
is(OpenILS::Application::AppUtils->extract_marc_price('€12.99'), '12.99',
   'extract_marc_price: Euro symbol');
is(OpenILS::Application::AppUtils->extract_marc_price('¥1200'), '1200',
   'extract_marc_price: Japanese Yen');

# Currency codes
is(OpenILS::Application::AppUtils->extract_marc_price('Rs15.76'), '15.76',
   'extract_marc_price: currency code Rs');
is(OpenILS::Application::AppUtils->extract_marc_price('CAD 45.00'), '45.00',
   'extract_marc_price: currency code CAD with space');
is(OpenILS::Application::AppUtils->extract_marc_price('USD 99.99'), '99.99',
   'extract_marc_price: currency code USD with space');

# Multiple prices - should return first one
is(OpenILS::Application::AppUtils->extract_marc_price('Rs15.76 ($5.60 U.S.)'), '15.76',
   'extract_marc_price: multiple prices, returns first');
is(OpenILS::Application::AppUtils->extract_marc_price('For sale ($450.00) or rent ($45.00)'), '450.00',
   'extract_marc_price: complex multiple price statement');
is(OpenILS::Application::AppUtils->extract_marc_price('$8.95 ($5.00 U.S.)'), '8.95',
   'extract_marc_price: price with parenthetical qualifier');

# Thousands separators
is(OpenILS::Application::AppUtils->extract_marc_price('$1,234.56'), '1234.56',
   'extract_marc_price: thousands separator removed');
is(OpenILS::Application::AppUtils->extract_marc_price('€10,000.00'), '10000.00',
   'extract_marc_price: multiple thousands separators');

# Edge cases and special values
is(OpenILS::Application::AppUtils->extract_marc_price('$0.00'), '0.00',
   'extract_marc_price: zero value with decimals');
is(OpenILS::Application::AppUtils->extract_marc_price('$0'), '0',
   'extract_marc_price: zero value without decimals');
is(OpenILS::Application::AppUtils->extract_marc_price('0.99'), '0.99',
   'extract_marc_price: price without currency symbol');
is(OpenILS::Application::AppUtils->extract_marc_price('123'), '123',
   'extract_marc_price: whole number without symbol');

# Non-price text - should return undef
is(OpenILS::Application::AppUtils->extract_marc_price('Rental material'), undef,
   'extract_marc_price: non-price text returns undef');
is(OpenILS::Application::AppUtils->extract_marc_price('Free'), undef,
   'extract_marc_price: "Free" returns undef');
is(OpenILS::Application::AppUtils->extract_marc_price('Not for sale'), undef,
   'extract_marc_price: "Not for sale" returns undef');
is(OpenILS::Application::AppUtils->extract_marc_price(''), undef,
   'extract_marc_price: empty string returns undef');
is(OpenILS::Application::AppUtils->extract_marc_price(undef), undef,
   'extract_marc_price: undef input returns undef');
