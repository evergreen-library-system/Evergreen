#!perl

use strict; use warnings;
use Test::More tests => 6;
use Test::MockModule;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Apache2::Const -compile => qw(OK);
use CGI;

use_ok('OpenILS::WWW::EGCatLoader');
can_ok( 'OpenILS::WWW::EGCatLoader', 'load_print_or_email_preview' );
can_ok( 'OpenILS::WWW::EGCatLoader', 'load_email_record' );

use constant ATEV_ID => '123456789';
use constant PATRON_USERNAME  => '99999359616';
use constant PATRON_PASSWORD  => 'demo123';

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
$script->authenticate({
        username => PATRON_USERNAME,
        password => PATRON_PASSWORD,
        type => 'opac'
    });
ok($script->authtoken, 'Have an authtoken');
my $authtoken = $script->authtoken;

my $loader_mock = Test::MockModule->new('OpenILS::WWW::EGCatLoader');
$loader_mock->mock(
  cgi => sub {
    my $cgi = CGI->new();
    $cgi->param('context_org', 1);
    $cgi->param('redirect_to', '/');
    return $cgi;},
);

my $email_mock = Test::MockModule->new('Email::Send');
$email_mock->mock(
  send => sub {}
);

my $ctx = {
  'authtoken' => $authtoken,
  'page_args' => [254],
  'get_aou' => sub {
    my $ou = Fieldmapper::actor::org_unit->new;
    $ou->id(1);
    return $ou;}
};

my $loader = new OpenILS::WWW::EGCatLoader(1, $ctx);

my $preview_response = $loader->load_print_or_email_preview('email');
is $preview_response, Apache2::Const::OK, 'Email preview delivers a good response';

my $event_id = $loader->ctx->{preview_record}->id();

unshift @{$loader->ctx->{page_args}}, $event_id;

my $response = $loader->load_email_record();
is $response, Apache2::Const::OK, 'Email record from OPAC delivers a good response';

1;