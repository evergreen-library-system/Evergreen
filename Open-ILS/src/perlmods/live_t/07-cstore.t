#!perl
use strict; use warnings;

use Test::More tests => 4;

diag("Tests CSTORE");

use Digest::MD5 qw(md5_hex);
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor (':funcs');
my $U = 'OpenILS::Application::AppUtils';

my $script = OpenILS::Utils::TestUtils->new;
$script->bootstrap;

my $e = new_editor;
$e->init;

# Here follow various tests for SQL injection attempts
# via forbidden invocations of json_query(). Since we're
# testing by attempting to inappropriately change a user
# password, each subtest is wrapped in an explict transaction
# so that (a) a successful SQL injection in one subtest doesn't
# invalidate subsequent subtests and (b) the password of that
# user doesn't stay changed once the test script is done.

# random password to use for the duration of the test
my $expected_password = md5_hex(time . $$ . rand());

sub set_user_1_password {
    $e->json_query({
        from => ['actor.change_password', 1, $expected_password]
    });
}

subtest('can invoke functions via json_query directly', sub {
    plan tests => 1;

    $e->xact_begin;
    set_user_1_password();
    ok $U->verify_migrated_user_password($e, 1, $expected_password), 'json_query can invoke actor.change_password directly';
    $e->rollback;
});

subtest('using functions in a where clause', sub {
    plan tests => 3;

    $e->xact_begin;
    set_user_1_password();
    my $res = $e->json_query({
        from => 'acp',
        where => {barcode => ['xml_escape', 'CONC90000436']}
    });
    is scalar(@{$res}), 1, 'it can use a function to modify a param';

    $res = $e->json_query({
        from => 'acp',
        where => {id => {'=' => ['(SELECT 1 FROM actor.change_password(1,\'squid\'))--']}}
    });
    ok $e->event, 'it rejects SQL injection';
    ok $U->verify_migrated_user_password($e, 1, $expected_password), 'confirmed that injection attempt was ineffective';
    $e->rollback;
});

subtest('using functions in an alias', sub {
    plan tests => 1;

    $e->xact_begin;
    set_user_1_password();
    my $res = $e->json_query({
        from => 'aou',
        where => {id => 1},
        select => { aou => [
            'id',
            {
                column => 'shortname',
                alias => 'alias_foo" FROM actor.org_unit AS aou WHERE 1=1;SELECT actor.change_password(1,\'squid\')--'
            }
        ]},
    });
    ok $U->verify_migrated_user_password($e, 1, $expected_password), 'confirmed that injection attempt via alias was ineffective';
    $e->rollback;
});

subtest('using functions in a result_field', sub {
    plan tests => 1;

    $e->xact_begin;
    set_user_1_password();
    my $res = $e->json_query({
        from => 'aou',
        where => {id => 9},
        select => { aou => [{
            transform => 'actor.org_unit_ancestors',
            column => 'id',
            result_field => 'id" FROM actor.org_unit AS aou WHERE 1=1;SELECT actor.change_password(1,\'squid\')--',
            params => [],
        }]},
    });

    # Note that this was already caught prior to the LP#2147196 fixes
    ok $U->verify_migrated_user_password($e, 1, $expected_password), 'confirmed that injection attempt via alias was ineffective';
    $e->rollback;
});
