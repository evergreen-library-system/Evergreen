#!perl
use strict; use warnings;
use Test::More tests => 6;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use LWP::UserAgent;
use File::Fetch;
use HTTP::Request::Common qw(POST);
use FindBin;

diag("test image uploader");

my $U = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');

#    <form method="POST" enctype="multipart/form-data" action="/jacket-upload">
#        <input type="file" name="jacket_upload">
#        <input type="text" name="ses">
#        <input type="text" name="bib_record">
#        <input type="submit">
#    </form>

my $target = "http://127.0.0.1/jacket-upload";

my $ua = new LWP::UserAgent;
my $req = POST(
    $target,
    Content_Type => 'multipart/form-data',
    Content => [
        # we're going for an image parse error
        jacket_upload => [ "$FindBin::Bin/34-lp1787968-cover-uploader.t" ],
        bib_record => 1,
        ses => $authtoken
    ]
);

my $response = $ua->request($req);
ok( $response->is_success(), 'HTTP POST was successful');
ok( $response->content() eq '"parse error"', 'Received expected parse error for non-image upload');

$ua = new LWP::UserAgent;
$req = POST(
    $target,
    Content_Type => 'multipart/form-data',
    Content => [
        jacket_upload => [ "$FindBin::Bin/../../../web/images/green_check.png" ],
        bib_record => 1,
        ses => $authtoken
    ]
);
$response = $ua->request($req);
ok( $response->is_success(), 'HTTP POST was successful');
ok( $response->content() eq '1', 'Received expected response for an image upload');

my $url = 'http://localhost/opac/extras/ac/jacket/small/r/1';
my $ff = File::Fetch->new(uri => $url);
my $file = $ff->fetch( to => '/tmp' ) or die $ff->error;
diag("Downloaded $url as $file");

my $filetype = `file $file`;
diag($filetype);
ok( $filetype =~ /PNG/, 'Downloaded a PNG file from target location');
