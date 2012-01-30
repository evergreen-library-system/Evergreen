#!perl -T

use Test::More tests => 22;

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
