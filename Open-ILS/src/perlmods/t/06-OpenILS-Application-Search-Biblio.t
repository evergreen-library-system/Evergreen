#!perl -T

use warnings;
use strict;

use Test::More tests => 2;
use Test::MockObject;
use Test::MockModule;
use_ok 'OpenILS::Application::Search::Biblio';

subtest 'fetch_in_scope_lassos' => sub {
    plan tests => 2;

    my $mock_map = Test::MockObject->new;
    $mock_map->set_always( 'lasso', 5 );

    my $mock_lasso = Test::MockObject->new;
    $mock_lasso->set_always( 'name', 'Law Libraries' );

    subtest 'when staff' => sub {
        plan tests => 3;

        my $mock_appsession = Test::MockObject->new;
        $mock_appsession->set_true( 'respond' );

        my $mock_editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
            ->mock(search_actor_org_lasso_map => [$mock_map])
            ->define(search_actor_org_lasso => sub {
                my ($self, $criteria) = @_;
                is_deeply $criteria,
                    { '-or' => { global => 't', id => { in => [5]} } },
                    'Searches for the lasso in the appropriate maps';
                [$mock_lasso]
            });

        OpenILS::Application::Search::Biblio->fetch_in_scope_lassos(
            $mock_appsession,
            103
        );

        $mock_appsession->called_ok('respond', 'responded to the request');
        is_deeply($mock_appsession->call_args_pos(1, 1), $mock_lasso, 'included a lasso in the response');
    };

    subtest 'when opac' => sub {
        plan tests => 3;

        my $mock_appsession = Test::MockObject->new;
        $mock_appsession->set_true( 'respond' );

        my $mock_editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
            ->mock(search_actor_org_lasso_map => [$mock_map])
            ->define(search_actor_org_lasso => sub {
                my ($self, $criteria) = @_;
                is_deeply $criteria,
                    { opac_visible => 't', '-or' => { global => 't', id => { in => [5]} } },
                    'Searches for the lasso in the appropriate maps limited to opac_visible';
                [$mock_lasso]
            });
        my $biblio_mock = Test::MockObject->new;
        $biblio_mock->set_always('api_name' => 'open-ils.search.fetch_context_library_groups.opac');

        OpenILS::Application::Search::Biblio::fetch_in_scope_lassos(
            $biblio_mock,
            $mock_appsession,
            103
        );

        $mock_appsession->called_ok('respond', 'responded to the request');
        is_deeply($mock_appsession->call_args_pos(1, 1), $mock_lasso, 'included a lasso in the response');
    };
};
