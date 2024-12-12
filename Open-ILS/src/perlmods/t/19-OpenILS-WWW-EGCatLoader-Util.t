#!perl -T

use strict; use warnings;
use Test::More tests => 3;
use Test::MockModule;
use Test::MockObject;

use_ok 'OpenILS::WWW::EGCatLoader';
use_ok 'OpenILS::WWW::EGCatLoader::Util';

subtest 'load_lassos' => sub {
    plan tests => 3;
    my $ctx = {search_ou => 3};
    my $logger = Test::MockObject->new;
    $logger->set_true('info');
    my $apache = Test::MockObject->new;
    $apache->set_always('log', $logger);
    my $cat_loader = OpenILS::WWW::EGCatLoader->new($apache, $ctx);

    my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
        ->redefine(simplereq => sub {
            my ($self, $app, $method, $id) = @_;
            is $app, 'open-ils.search', 'calls the correct app';
            is $method, 'open-ils.search.fetch_context_library_groups.opac.atomic', 'calls the correct method';
            is $id, 3, 'calls the correct org id';
            return [];
        });
    $cat_loader->load_lassos;
}
