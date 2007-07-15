#!/usr/bin/perl
# turns the orgTree and orgTypes into js files

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;

die "usage: perl org_tree_html_options.pl <bootstrap_config> <output_file>" unless $ARGV[1];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

open FILE, ">$ARGV[1]";

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $ses = OpenSRF::AppSession->create("open-ils.actor");
my $tree = $ses->request("open-ils.actor.org_tree.retrieve")->gather(1);

print_option($tree);

$ses->disconnect();
close FILE;



sub print_option {
	my $node = shift;
	return unless ($node->opac_visible =~ /^[y1t]+/i);
	my $depth = $node->ou_type - 1;
	my $sname = $node->shortname;
	my $name = $node->name;
	my $kids = $node->children;
	print FILE "<option value='$sname'><pre>" . '&nbsp;&nbsp;&nbsp;'x$depth . "</pre>$name</option>\n";
	print_option($_) for (@$kids);
}

