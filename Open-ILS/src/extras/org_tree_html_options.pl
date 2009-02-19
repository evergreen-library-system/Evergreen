#!/usr/bin/perl
# turns the orgTree and orgTypes into a static HTML option list

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use Unicode::Normalize;
use Data::Dumper;

die "usage: perl org_tree_html_options.pl <bootstrap_config> <output_file>" unless $ARGV[1];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

open FILE, ">$ARGV[1]";

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $ses = OpenSRF::AppSession->create("open-ils.actor");
my $tree = $ses->request("open-ils.actor.org_tree.retrieve")->gather(1);

my @types;
my $aout = $ses->request("open-ils.actor.org_types.retrieve")->gather(1);
foreach my $type (@$aout) {
	$types[int($type->id)] = $type;
}

print_option($tree);

$ses->disconnect();
close FILE;



sub print_option {
	my $node = shift;
	return unless ($node->opac_visible =~ /^[y1t]+/i);

	my $depth = $types[$node->ou_type]->depth;
	my $sname = entityize($node->shortname);
	my $name = entityize($node->name);
	my $kids = $node->children;

	print FILE "<option value='$sname'>" . '&#160;&#160;&#160;'x$depth . "$name</option>\n";
	print_option($_) for (@$kids);
}

sub entityize {
        my $stuff = shift || return "";
        $stuff =~ s/\</&lt;/og;
        $stuff =~ s/\>/&gt;/og;
        $stuff =~ s/\&/&amp;/og;
        $stuff = NFD($stuff);
        $stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
        return $stuff;
}

