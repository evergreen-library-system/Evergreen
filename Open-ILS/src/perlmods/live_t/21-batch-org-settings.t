#!perl
use strict; use warnings;
use Test::More tests => 180; # 15 orgs * 12 settings
use OpenILS::Utils::TestUtils;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

diag("Tests batch org setting retrieval");

my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $org_ids = [1 .. 15];
# All settings at time of writing.  None of these have view perms.
my @settings = qw/
    circ.patron_search.diacritic_insensitive
    circ.checkout_auto_renew_age
    cat.label.font.weight
    cat.spine.line.height
    circ.grace.extend
    cat.label.font.size
    circ.booking_reservation.default_elbow_room
    cat.spine.line.width
    lib.info_url
    circ.hold_go_home_interval
    cat.label.font.family
    cat.spine.line.margin
/;

# compare the values returned from the batch-by-org setting to the
# traditional setting value lookup call.
for my $setting (@settings) {
    my %batch_settings = 
        $U->ou_ancestor_setting_batch_by_org_insecure($org_ids, $setting);

    for my $org_id (@$org_ids) {
        my $value = $U->ou_ancestor_setting_value($org_id, $setting);
        is($value, $batch_settings{$org_id}->{value}, 
            "Value matches for setting $setting and org $org_id");
    }
}


