#!perl

use Test::More tests => 8;

diag("Test transferring holds with parts.");

use constant WORKSTATION_NAME => 'BR1-test-26-lp1411422-transferring-items-volumes-with-parts.t';
use constant WORKSTATION_LIB => 4;

use strict; use warnings;

use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;

our $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

our $e = new_editor(xact => 1);
$e->init;


# setup workstation and login
# -------------
setupLogin();

# Find a copy with at least one part
# -------------

my $copy = $e->search_asset_copy([
{ deleted => 'f' },
{
    join => {
        acpm => {
            type => 'inner',
            join => {
                bmp => { type => 'left' },
            }
        }
    },
    flesh => 1,
    flesh_fields => { acp => ['parts']},
    limit => 1
}
])->[0];

diag("Using copy ". $copy->id);
my $parts = $copy->parts;
my $oldcallnumber = $copy->call_number;
my $part_objs = [];
my $part;

foreach my $spart (@$parts) {
    $part = $spart;
}
diag("Copy part label -> ". $part->label);

diag("Copy call number ". $oldcallnumber);

$oldcallnumber = $e->search_asset_call_number({id => $oldcallnumber, deleted => 'f'})->[0];

diag("Copy attached to bib ". $oldcallnumber->record);

# Find a bib without parts
# -------------
my $sdestbib = $e->search_biblio_record_entry([
{
id =>
    {
        'not in' =>
            { "from" => 'bmp',
                'select' =>  { "bmp" => [ 'record' ] }
            }
    },
deleted => 'f' },
{ limit => 3 }

]);

my $destbib;
foreach(@{$sdestbib}) {
    if ($_->id > -1) {
        $destbib = $_;
        last;
    }
}


diag("Using this non parted bib ". $destbib->id);

# Create a new volume for the copy to transfer to
# -------------
my $newcall = Fieldmapper::asset::call_number->new;

$newcall->owning_lib($oldcallnumber->owning_lib);
$newcall->record($destbib->id);
$newcall->creator($oldcallnumber->creator);
$newcall->editor($oldcallnumber->editor);
$newcall->label('Test copy transfer with parts');


my $stat = $e->create_asset_call_number($newcall);
ok($stat, 'Created temporary volume on bib '.$destbib->id);

diag( "New call number id: " . $newcall->id );

# freshen up the variable
# get all the rest of the values from the DB
$newcall = $e->search_asset_call_number({id => $newcall->id})->[0];

# save changes so that the storage request has access
$e->commit;

# make the transfer
# -------------
my @copy_id_array = ($copy->id);
my $storage = $script->session('open-ils.cat');
my $req = $storage->request(
    'open-ils.cat.transfer_copies_to_volume',  $script->authtoken, $newcall->id, \@copy_id_array )->gather(1);

# Did the code create a new part on the destination bib?
# -------------
$e->xact_begin;

my $destparts = $e->search_biblio_monograph_part({record => $newcall->record, label => $part->label, deleted => 'f'})->[0];
ok($destparts, 'Copy transfer with parts success on bib '.$destbib->id);

is($destparts->label, $part->label, 'Part labels match and everything!');

# Now test transferring volumes,
# might as well transfer it back to the old bib
# -------------

my @vols = ($newcall->id);
my $docid = $oldcallnumber->record;
my $args = {lib => $oldcallnumber->owning_lib, docid => $docid, volumes => \@vols };
$storage = $script->session('open-ils.cat');
$req = $storage->request(
    'open-ils.cat.asset.volume.batch.transfer',
    $script->authtoken,
    $args
    )->gather(1);
# Make sure that the old bib received the part
my $destparts2 = $e->search_biblio_monograph_part({record => $oldcallnumber->record, label => $part->label, deleted => 'f'})->[0];
ok($destparts2, 'Volume transfer with parts success on bib '.$oldcallnumber->record);
is($destparts->label, $part->label, 'Part labels match and everything!');


# Reverse the data
# -------------
$storage = $script->session('open-ils.cat');
$req = $storage->request(
    'open-ils.cat.transfer_copies_to_volume',  $script->authtoken, $oldcallnumber->id, \@copy_id_array )->gather(1);

$stat = $e->delete_asset_call_number($newcall);

$e->xact_commit;


sub setupLogin {

    my $workstation = $e->search_actor_workstation([ {name => WORKSTATION_NAME, owning_lib => WORKSTATION_LIB } ])->[0];

    if(!$workstation )
    {
        $script->authenticate({
            username => 'admin',
            password => 'demo123',
            type => 'staff'});
        ok( $script->authtoken, 'Have an authtoken');
        my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
        ok( ! ref $ws, 'Registered a new workstation');
        $script->logout();
    }

    $script->authenticate({
        username => 'admin',
        password => 'demo123',
        type => 'staff',
        workstation => WORKSTATION_NAME});
    ok( $script->authtoken, 'Have an authtoken associated with the workstation');
}

