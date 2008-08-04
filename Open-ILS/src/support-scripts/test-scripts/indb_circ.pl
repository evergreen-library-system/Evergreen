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
    'org=i' => \$org_id,
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
            alias => 'matchpoint'
        }]
    },
    from => 'aou',
    where => {id => $org_id}
};

my $e = new_editor();

my $start = time;
my $mp_id = $e->json_query($CIRC_TEST)->[0]->{matchpoint};

my $rule_set = $e->search_config_circ_matrix_ruleset([
    {matchpoint => $mp_id},
    {   flesh => 1,
        flesh_fields => {
            'ccmrs' => ['duration_rule', 'recurring_fine_rule', 'max_fine_rule']
        }
    }
])->[0];

my $rundur = time - $start;

my $cp = $e->retrieve_asset_copy($copy_id);
my ($dur, $recf);

# get the actual duration
if($cp->loan_duration == 1) {
    $dur = $rule_set->duration_rule->shrt;
} elsif($cp->loan_duration == 2) {
    $dur = $rule_set->duration_rule->normal;
} else {
    $dur = $rule_set->duration_rule->extended;
}

# get the recurring fine level
if($cp->fine_level == 1) {
    $recf = $rule_set->recurring_fine_rule->low;
} elsif($cp->fine_level == 2) {
    $recf = $rule_set->recurring_fine_rule->normal;
} else {
    $recf = $rule_set->recurring_fine_rule->high;
}

print "Duration [".$rule_set->duration_rule->name."] = $dur\n";
print "Recurring fines [".$rule_set->recurring_fine_rule->name."; interval='".
    $rule_set->recurring_fine_rule->recurance_interval."'] = \$$recf\n";
print "Max fine [".$rule_set->max_fine_rule->name."] = \$".$rule_set->max_fine_rule->amount."\n";
print "took: $rundur\n";


