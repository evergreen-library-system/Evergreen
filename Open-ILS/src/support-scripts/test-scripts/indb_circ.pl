#!/usr/bin/perl
require '../oils_header.pl';
use vars qw/$authtoken/;
use strict; use warnings;
use Time::HiRes qw/time/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Data::Dumper;
use Getopt::Long;

# ---------------------------------------------------------------
# Initial in-db-circ test code
# This script takes an org, user, and copy ID and prints out the
# circulation rules that would apply
# ---------------------------------------------------------------

my ($config, $org_id, $user_id, $copy_id, $copy_barcode) = 
    ('/openils/conf/opensrf_core.xml', 326, 3, 301313, undef);

GetOptions(
    'org=o' => \$org_id,
    'user=i' => \$user_id,
    'copy=i' => \$copy_id,
    'barcode=s' => \$copy_barcode,
);

osrf_connect($config);

my $CIRC_TEST = {
    select => {
        aou => [{
            transform => 'action.item_user_circ_test',
            column => 'id',
            params => [$copy_id, $user_id],
            result_field => 'matchpoint',
        }]
    },
    from => 'aou',
    where => {id => $org_id}
};

my $e = new_editor();

my $mp_id = $e->json_query($CIRC_TEST)->[0]->{id};
my $mp = $e->retrieve_config_circ_matrix_ruleset([
    $mp_id,
    {   flesh => 1,
        flesh_fields => {
            'ccmrs' => ['duration_rule', 'recurring_fine_rule', 'max_fine_rule']
        }
    }
]);

my $cp = $e->retrieve_asset_copy($copy_id);
my ($dur, $recf);

# get the actual duration
if($cp->loan_duration == 1) {
    $dur = $mp->duration_rule->shrt;
} elsif($cp->loan_duration == 2) {
    $dur = $mp->duration_rule->normal;
} else {
    $dur = $mp->duration_rule->extended;
}

# get the recurring fine level
if($cp->fine_level == 1) {
    $recf = $mp->recurring_fine_rule->low;
} elsif($cp->fine_level == 2) {
    $recf = $mp->recurring_fine_rule->normal;
} else {
    $recf = $mp->recurring_fine_rule->high;
}


print "Duration [".$mp->duration_rule->name."] = $dur\n";
print "Recurring fines [".$mp->recurring_fine_rule->name."; interval='".
    $mp->recurring_fine_rule->recurance_interval."'] = \$$recf\n";
print "Max fine [".$mp->max_fine_rule->name."] = \$".$mp->max_fine_rule->amount."\n";


