#!/usr/bin/perl
use strict; use warnings;

# ------------------------------------------------------------
# turns the orgTree and orgTypes into js files
# ------------------------------------------------------------

use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;

die "usage: perl org_tree_js.pl <bootstrap_config>" unless $ARGV[0];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

# must be loaded after the IDL is parsed
require OpenILS::Utils::CStoreEditor;

warn "removing OrgTree from the cache...\n";
my $cache = OpenSRF::Utils::Cache->new;
$cache->delete_cache('orgtree');

# fetch the org_unit's and org_unit_type's
my $e = OpenILS::Utils::CStoreEditor->new;
my $types = $e->retrieve_all_actor_org_unit_type;
my $tree = $e->request(
    'open-ils.cstore.direct.actor.org_unit.search.atomic',
    {id => {"!=" => undef}},
    {order_by => {aou => 'name'}}
);


sub val {
    my $v = shift;
    return 'null' unless defined $v;

    # required for JS code this is checking truthness 
    # without using isTrue() (1/0 vs. t/f)
    return 1 if $v eq 't';
    return 0 if $v eq 'f';

    $v =~ s/([\x{0080}-\x{fffd}])/sprintf('\u%04x',ord($1))/sgoe;

    return "\"$v\"";
}

my $pile = "var _l = [";

my @array;
for my $o (@$tree) {
	my ($i,$t,$p,$n,$v,$s) = ($o->id,$o->ou_type,$o->parent_ou,val($o->name),val($o->opac_visible),val($o->shortname));
    $p ||= 'null';
	push @array, "[$i,$t,$p,$n,$v,$s]";
}

$pile .= join ',', @array;
$pile .= "]; /* Org Units */ \n";


$pile .= 'var globalOrgTypes = [';
for my $t (@$types) {
    my ($u,$v,$d,$i,$n,$o,$p) = (val($t->can_have_users),val($t->can_have_vols),$t->depth,$t->id,val($t->name),val($t->opac_label),$t->parent);
    $p ||= 'null';
    $pile .= "new aout([null,null,null,null,$u,$v,$d,$i,$n,$o,$p]), ";
}
$pile =~ s/, $//; # remove trailing comma
$pile .= ']; /* OU Types */';

print "$pile\n";


