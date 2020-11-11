#!perl

use strict; use warnings;
use Test::More tests => 2;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use FindBin;

diag('Test patron loader script');

my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

$script->authenticate({
    username => 'admin', # local administrator at BR1
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');

my $e = new_editor(xact => 1);
$e->init;

sub check_patron1 {
    my $first_patron = $e->search_actor_user({usrname => '77', deleted => 0})->[0];
    ok($first_patron, 'Added usrname from CSV');
    is($first_patron->profile, 2, 'Assigned Patrons profile');
    is($first_patron->first_given_name, 'Jane', 'Added first_given_name from CSV');
    is($first_patron->family_name, 'Doe', 'Added family_name from CSV');
    is($first_patron->email, 'really@fake.email', 'Added email from first email column in CSV');
    is($first_patron->dob, '1900-07-18', 'Added date of birth from CSV');
    is($first_patron->home_ou, 4, 'Added BR1 as home_ou, from CSV');
    my $first_card = $e->search_actor_card({id => $first_patron->card, active => 1, barcode => '77'})->[0];
    ok($first_card, 'Added card from CSV');
    is($first_patron->active, 't', 'Added active from CSV');
    is($first_patron->barred, 'f', 'Added barred from CSV');
    is($first_patron->juvenile, 't', 'Added juvenile from CSV');
    my $first_address = $e->search_actor_user_address({id => $first_patron->mailing_address, usr => $first_patron->id})->[0];
    ok($first_address, 'Added address from CSV');
    is($first_address->street1, '123 Home Ave', 'Added street1 from CSV');
    is($first_address->city, 'Whoville', 'Added city from CSV');
    return;
}

sub check_patron2 {
    my $second_patron = $e->search_actor_user({usrname => '99', deleted => 0})->[0];
    ok($second_patron, 'Added usrname from CSV');
    is($second_patron->profile, 2, 'Assigned Patrons profile');
    is($second_patron->first_given_name, 'Jack', 'Added first_given_name from CSV');
    is($second_patron->family_name, 'Doe', 'Added family_name from CSV');
    is($second_patron->email, 'more@fake.email', 'Added email from first email column in CSV');
    is($second_patron->dob, '1901-07-18', 'Added date of birth from CSV');
    is($second_patron->home_ou, 4, 'Added BR1 as home_ou, from CSV');
    my $second_card = $e->search_actor_card({id => $second_patron->card, active => 1, barcode => '99'})->[0];
    ok($second_card, 'Added card from CSV');
    is($second_patron->active, 't', 'Added active from CSV');
    is($second_patron->barred, 'f', 'Added barred from CSV');
    is($second_patron->juvenile, 't', 'Added juvenile from CSV');
    my $second_address = $e->search_actor_user_address({id => $second_patron->mailing_address, usr => $second_patron->id})->[0];
    ok($second_address, 'Added address from CSV');
    is($second_address->street1, 'Street of the Lifted Lorax', 'Added street1 from CSV');
    is($second_address->city, 'Whoville Lower Metro', 'Added city from CSV');
    return;
}

subtest 'can load patrons from a CSV' => sub {
    plan tests => 8;
    # Assumes that the loader has been installed to
    # a directory in the test runner's $PATH
    my $original_patron_count = scalar(@{$e->search_actor_user({deleted => 0})});
    my $other_patrons = $e->search_actor_user({deleted => 0, family_name => {'!=' => 'Doe'}});

    my $output = `patron_loader.pl --file $FindBin::Bin/data/patrons-to-import.csv --org_unit=BR1`;
    ok($output, 'runs without error');

    my $updated_patron_count = scalar(@{$e->search_actor_user({deleted => 0})});
    is($updated_patron_count - $original_patron_count, 2, 'Added 2 patrons');
    my $updated_other_patrons = $e->search_actor_user({deleted => 0, family_name => {'!=' => 'Doe'}});
    is_deeply($other_patrons, $updated_other_patrons, 'Other patrons have not been affected');

    subtest 'patron 1 is loaded correctly' => sub {
        plan tests => 14;
        check_patron1();
    };

    subtest 'patron 2 is loaded correctly' => sub {
        plan tests => 14;
        check_patron2();
    };

    subtest 'logging' => sub {
        plan tests => 1;
        my $log_entries = scalar(@{ $e->search_actor_patron_loader_log({event => 'session closing normally'}) });
        ok($log_entries, 'it logs to the database');
    };

    subtest 'idempotency' => sub {
        plan tests => 29;
        $output = `patron_loader.pl --file $FindBin::Bin/data/patrons-to-import.csv --org_unit=BR1`;
        ok($output, 'runs without error');
        check_patron1();
        check_patron2();
    };

    subtest 'cleanup' => sub {
        plan tests => 1;
        my $loaded_patrons = $e->search_actor_user({family_name => 'Doe', deleted => 0});
        $e->xact_begin;
        $e->json_query({from => ['actor.usr_delete', $loaded_patrons->[0]->id, undef]});
        $e->json_query({from => ['actor.usr_delete', $loaded_patrons->[1]->id, undef]});
        $e->xact_commit;
        $loaded_patrons = $e->search_actor_user({family_name => 'Doe', deleted => 0});
        is(scalar(@{ $loaded_patrons }), '0', 'Deleted test patrons');
    };
};
