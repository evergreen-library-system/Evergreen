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
my $tree = $e->retrieve_all_actor_org_unit;
my $types = $e->retrieve_all_actor_org_unit_type;


sub val {
    my $v = shift;
    return 'null' unless defined $v;

    # required for JS code this is checking truthness 
    # without using isTrue() (1/0 vs. t/f)
    return 1 if $v eq 't';
    return 0 if $v eq 'f';

    return "\"$v\"";
}

my $pile = "var _l = [";

my @array;
for my $o (@$tree) {
	my ($i,$t,$p,$n,$v) = ($o->id,$o->ou_type,val($o->parent_ou),$o->name,val($o->opac_visible));
    $p ||= 'null';
	push @array, "[$i,$t,$p,\"$n\",$v]";
}

$pile .= join ',', @array;
$pile .= "];\n";


$pile .= 'globalOrgTypes = [';
for my $t (@$types) {
    $pile .= 'new aout([null,null,null,null,'.
        val($t->can_have_users).','.
        val($t->can_have_vols).','.
        val($t->depth).','.
        val($t->id).','.
        val($t->name).','.
        val($t->opac_label).','.
        val($t->parent).']), ';
}
$pile =~ s/, $//; # remove trailing comma
$pile .= '];';

print "$pile\n";


