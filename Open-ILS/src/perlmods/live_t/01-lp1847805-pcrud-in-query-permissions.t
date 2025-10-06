#!perl
# Yes, this is a Perl test for some C code, but
# it seemed way easier to write a meaningful
# integration test here than with libcheck :-D

use strict; use warnings;
use Test::More tests => 9;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

diag('LP1847805: open-ils.pcrud in-query permission testing and count-only search variant');

# ----- First we test cstore for count, and gather data for comparison

my $cstore_ses = $script->session('open-ils.cstore');
$cstore_ses->connect();

my $cstore_tree = $cstore_ses->request(
    'open-ils.cstore.direct.permission.grp_tree.search',
    {parent => undef},
    {flesh => -1, flesh_fields => {pgt => ["children"]}, order_by => [{class=>"pgt", field => "id"}]}
)->gather(1);
isa_ok($cstore_tree, 'Fieldmapper::permission::grp_tree', 'cstore-provided group tree');

my $cstore_list = $cstore_ses->request(
    'open-ils.cstore.direct.permission.grp_tree.search.atomic',
    {id => {"!=" => undef}},
    {order_by => [{class => "pgt", field => "id"}]}
)->gather(1);
isa_ok($$cstore_list[0], 'Fieldmapper::permission::grp_tree', 'cstore-provided group list');
is(scalar(@$cstore_list), 23, 'Correct cstore-provided org list length');

my $cstore_count = $cstore_ses->request(
    'open-ils.cstore.direct.permission.grp_tree.count',
    {id => {"!=" => undef}}
)->gather(1);
is($cstore_count, 23, 'Correct pcrud-provided org count');

# ----- done with cstore test and data gathering



# ----- Now test pcrud against cstore data, and expected results

# Login as a staff user, which is needed for pcrud pgt fetches
my $credentials = {
    username => 'br1breid',
    password => 'demo123',
    type => 'staff'
};
my $authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

my $pcrud_ses = $script->session('open-ils.pcrud');
$pcrud_ses->connect();

my $pcrud_tree = $pcrud_ses->request(
    'open-ils.pcrud.search.pgt',
    $authtoken,
    {parent => undef},
    {flesh => -1, flesh_fields => {pgt => ["children"]}, order_by => [{class=>"pgt", field => "id"}]}
)->gather(1);
isa_ok($pcrud_tree, 'Fieldmapper::permission::grp_tree', 'pcrud-provided group tree');

my $pcrud_list = $pcrud_ses->request(
    'open-ils.pcrud.search.pgt.atomic',
    $authtoken,
    {id => {"!=" => undef}},
    {order_by => [{class => "pgt", field => "id"}]}
)->gather(1);
isa_ok($$pcrud_list[0], 'Fieldmapper::permission::grp_tree', 'pcrud-provided group list');
is(scalar(@$pcrud_list), 23, 'Correct pcrud-provided org list length');

my $pcrud_count = $pcrud_ses->request(
    'open-ils.pcrud.count.pgt',
    $authtoken,
    {id => {"!=" => undef}}
)->gather(1);
is($pcrud_count, 23, 'Correct pcrud-provided org count');

# compare pcrud data with cstore, must be the same
is_deeply($pcrud_tree, $cstore_tree, 'pcrud group tree matches cstore version');
is_deeply($pcrud_list, $cstore_list, 'pcrud group list matches cstore version');

