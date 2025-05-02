#!perl

use strict; use warnings;

use Test::More tests => 2;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

diag('Test the EResourceLinkClick::Click module');

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
our $apputils = "OpenILS::Application::AppUtils";
my $e = new_editor;
$e->init;

BEGIN { use_ok('OpenILS::WWW::EResourceLinkClick::Click'); }

subtest('add_click', sub {
    plan tests => 2;

    subtest('when the global flag is off', sub {
        plan tests => 2;
        set_global_flag($e, 'f');

        my $response = OpenILS::WWW::EResourceLinkClick::Click->add_click(
            238,
            'http://example.com/ebookapi/t/001',
            'https://my-evergreen.org/eg/opac/results',
            'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0'
        );

        is($response, OpenILS::WWW::EResourceLinkClick::Click::NotConfigured, 'says that it is not configured');
        assert_no_clicks_added_to_db($e);
    });

    subtest('when the global flag is on', sub {
        plan tests => 5;
        set_global_flag($e, 't');

        subtest('when the referer did not come from the record or results page', sub {
            plan tests => 2;

            my $response = OpenILS::WWW::EResourceLinkClick::Click->add_click(
                238,
                'http://example.com/ebookapi/t/001',
                'https://some-non-eg-site/bad-path',
                'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0'
            );

            is($response, OpenILS::WWW::EResourceLinkClick::Click::BadInput, 'says that the input is bad');
            assert_no_clicks_added_to_db($e);
        });

        subtest('when user agent is a bot', sub {
                plan tests => 2;
                my $response = OpenILS::WWW::EResourceLinkClick::Click->add_click(
                    238,
                    'http://example.com/ebookapi/t/001',
                    'https://my-evergreen.org/eg/opac/results',
                    'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
                );

                is($response, OpenILS::WWW::EResourceLinkClick::Click::BadInput, 'says that the input is bad');
                assert_no_clicks_added_to_db($e);
        });

        subtest('when url does not exist on the record in question', sub {
                plan tests => 2;
                my $response = OpenILS::WWW::EResourceLinkClick::Click->add_click(
                    238,
                    'http://not-a-real-url/not-actually/on-the-record',
                    'https://my-evergreen.org/eg/opac/results',
                    'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
                );

                is($response, OpenILS::WWW::EResourceLinkClick::Click::BadInput, 'says that the input is bad');
                assert_no_clicks_added_to_db($e);
        });

        subtest('when input is valid', sub {
            plan tests => 2;
            my $response = OpenILS::WWW::EResourceLinkClick::Click->add_click(
                238,
                'http://example.com/ebookapi/t/001',
                'https://my-evergreen.org/eg/opac/results',
                'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0'
            );

            is($response, OpenILS::WWW::EResourceLinkClick::Click::Success, 'says that it is successful');
            my $rows = $e->search_action_eresource_link_click({record => 238});
            is(scalar(@{ $rows }), 1, 'adds the click to the database');

            delete_test_rows($e);
        });

        subtest('when bib record is associated with a course', sub {
            plan tests => 4;

            my $acmc = Fieldmapper::asset::course_module_course->new;
            $acmc->id(12345);
            $acmc->name('Introduction to cats');
            $acmc->course_number('CATS101');

            my $acmcm = Fieldmapper::asset::course_module_course_materials->new;
            $acmcm->course(12345);
            $acmcm->id(5678);
            $acmcm->record(238);
            $acmcm->temporary_record(0);
            $e->xact_begin;
            $e->create_asset_course_module_course( $acmc );
            $e->create_asset_course_module_course_materials( $acmcm );
            $e->xact_commit;

            my $response = OpenILS::WWW::EResourceLinkClick::Click->add_click(
                238,
                'http://example.com/ebookapi/t/001',
                'https://my-evergreen.org/eg/opac/results',
                'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0'
            );

            is($response, OpenILS::WWW::EResourceLinkClick::Click::Success, 'says that it is successful');
            my $rows = $e->search_action_eresource_link_click_course({course => 12345});
            is(scalar(@{ $rows }), 1, 'adds a click course mapping to the database');
            is($rows->[0]->course_name, 'Introduction to cats', 'adds the course name to the mapping');
            is($rows->[0]->course_number, 'CATS101', 'adds the course number to the mapping');

            delete_test_rows($e);
        });
    });
});

# Delete any rows that weren't deleted by the tests
# (e.g. if there was a test failure)
delete_test_rows($e);

sub set_global_flag {
    my ($editor, $value) = @_;
    my $flag = $e->retrieve_config_global_flag('opac.eresources.link_click_tracking');
    $flag->enabled($value);
    $editor->xact_begin;
    $editor->update_config_global_flag($flag);
    $editor->xact_commit;
}

sub assert_no_clicks_added_to_db {
    my $editor = shift;
    my $rows = $e->search_action_eresource_link_click({record => 238});
    is(scalar(@{ $rows }), 0, 'does not add any clicks to the database');
}

sub delete_test_rows {
    my $editor = shift;
    my $rows = $e->search_action_eresource_link_click({record => 238});
    $editor->xact_begin;
    foreach(@{$rows}) {
        $editor->delete_action_eresource_link_click($_);
    }
    $rows = $e->search_asset_course_module_course_materials({course => 12345});
    foreach(@{$rows}) {
        $editor->delete_asset_course_module_course_materials($_);
    }
    $rows = $e->search_asset_course_module_course({id => 12345});
    foreach(@{$rows}) {
        $editor->delete_asset_course_module_course($_);
    }
    $editor->xact_commit;
}

