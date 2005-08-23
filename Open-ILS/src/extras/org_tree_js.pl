
# turns the orgTree and orgTypes into js files

use OpenSRF::AppSession;
use OpenSRF::System;
use JSON;
use OpenILS::Utils::Fieldmapper;

die "usage: perl org_tree_js.pl <bootstrap_config>" unless $ARGV[0];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

my $ses = OpenSRF::AppSession->create("open-ils.storage");
my $tree = $ses->request("open-ils.storage.direct.actor.org_unit.retrieve.all.atomic")->gather(1);
my $types = $ses->request("open-ils.storage.direct.actor.org_unit_type.retrieve.all.atomic")->gather(1);

my $types_string = JSON->perl2JSON($types);
$types_string =~ s/\"/\\\"/g;

my $pile = "var _l = [";

my @array;
for my $o (@$tree) {
	my ($i,$t,$p,$n) = ($o->id,$o->ou_type,$o->parent_ou,$o->name);
	push @array, "[$i,$t,$p,\"$n\"]";
}
$pile .= join ',', @array;
$pile .= <<JS;
];
JS

$pile .= "var globalOrgTypes = JSON2js(\"$types_string\");";

print $pile;


$ses->disconnect();
