#!perl
# Yes, this is a Perl test for some C code, but
# it seemed way easier to write a meaningful
# integration test here than with libcheck :-D

use strict; use warnings;
use Test::More tests => 2;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

diag('LP108016: Pcrud returns a bad error status before complete');

# Login as a staff with limited permissions (just acq permissions in this case)
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
my $xact = $pcrud_ses->request(
    'open-ils.pcrud.transaction.begin',
    $script->authtoken
)->gather(1);

# As this user, try to do something forbidden: create a shelving location
my $acpl = Fieldmapper::asset::copy_location->new;
$acpl->owning_lib(1);
$acpl->name('My bad location');
my $request = $pcrud_ses->request(
    'open-ils.pcrud.create.acpl',
    $script->authtoken,
    $acpl
);
$request->recv();

is(error_code($request), 400, 'We get the expected error code');

sub error_code {
    my $request_to_check = shift;
    if ($request_to_check->failed() =~ /<(\d{3})>/ms) {
        return $1;
    }
    return 0;
}
