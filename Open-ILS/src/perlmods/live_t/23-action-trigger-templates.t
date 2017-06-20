#!perl

use strict;
use warnings;
use Test::More tests => 3;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

use OpenILS::Application::Trigger::Reactor;
my $r = "OpenILS::Application::Trigger::Reactor";

my $env = {
    carrier  => 1,
    number   => '',
    template => '[%- helpers.get_sms_gateway_email(carrier, number) -%]',
};
my $addr = $r->run_TT($env, 1);
is($addr, '', 'helpers.get_sms_gateway_email: no number means no SMS gateway address');

$env = {
    carrier  => 1,
    number   => '9015551212',
    template => '[%- helpers.get_sms_gateway_email(carrier, number) -%]',
};
$addr = $r->run_TT($env, 1);
is($addr, 'opensrf+9015551212@localhost', 'helpers.get_sms_gateway_email: get back a SMS gateway address');

$env = {
    carrier  => '',
    number   => '9015551212',
    template => '[%- helpers.get_sms_gateway_email(carrier, number) -%]',
};
$addr = $r->run_TT($env, 1);
is($addr, '', 'helpers.get_sms_gateway_email: no carrier means no SMS gateway address');
