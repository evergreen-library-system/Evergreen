
# turns the orgTree and orgTypes into js files

use OpenSRF::AppSession;
use OpenSRF::System;
use JSON;
die "usage: perl org_tree_js.pl <bootstrap_config>" unless $ARGV[0];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

my $ses = OpenSRF::AppSession->create("open-ils.actor");
my $req = $ses->request("open-ils.actor.org_tree.retrieve");

my $tree = $req->gather(1);

my $ses2 = OpenSRF::AppSession->create("open-ils.storage");
my $req2 = $ses2->request("open-ils.storage.direct.actor.org_unit_type.retrieve.all.atomic");
my $types = $req2->gather(1);

my $tree_string = JSON->perl2JSON($tree);
my $types_string = JSON->perl2JSON($types);

$tree_string =~ s/\"([0-9]+)\"/$1/g;
$tree_string =~ s/null//g;

$tree_string =~ s/\"/\\\"/g;
$types_string =~ s/\"/\\\"/g;


$tree_string = "var globalOrgTree = JSON2js(\"$tree_string\");";
$types_string = "var globalOrgTypes = JSON2js(\"$types_string\");";

print "$tree_string\n\n$types_string\n";


$ses->disconnect();
$ses2->disconnect();
