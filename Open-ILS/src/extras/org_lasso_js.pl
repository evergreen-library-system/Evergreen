#!/usr/bin/perl
use strict; use warnings;

# ------------------------------------------------------------
# turns the actor.org_lasso table into a js file
# ------------------------------------------------------------

use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::JSON;

die "usage: perl org_tree_js.pl <bootstrap_config>" unless $ARGV[0];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

# must be loaded after the IDL is parsed
require OpenILS::Utils::CStoreEditor;

# fetch the org_unit's and org_unit_type's
my $e = OpenILS::Utils::CStoreEditor->new;
my $lassos = $e->request(
    'open-ils.cstore.direct.actor.org_lasso.search.atomic',
    {id => {"!=" => undef}},
    {order_by => {lasso => 'name'}}
);

# We need at least one defined search group; otherwise, just generate an empty array
if (scalar(@$lassos) > 0) {
    print
        "var _lasso = [\n  new lasso(" .
        join( "),\n  new lasso(", map { OpenSRF::Utils::JSON->perl2JSON( bless($_, 'ARRAY') ) } @$lassos ) .
        ")\n]; /* Org Search Groups (Lassos) */ \n";
} else {
    print <<HERE;
var _lasso = [
]; /* Org Search Groups (Lassos) */
HERE
}

