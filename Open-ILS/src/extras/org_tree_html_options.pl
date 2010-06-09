#!/usr/bin/perl
# for each supported locale, turn the orgTree and orgTypes into a static HTML option list

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use Unicode::Normalize;
use Data::Dumper;
use File::Spec;

die "usage: perl org_tree_html_options.pl <bootstrap_config> <output_path> <output_file>" unless $ARGV[2];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

my $path = $ARGV[1];
my $filename = $ARGV[2];

my @types;

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

#Get our list of locales
my $session = OpenSRF::AppSession->create("open-ils.cstore");
my $locales = $session->request("open-ils.cstore.direct.config.i18n_locale.search.atomic", {"code" => {"!=" => undef}}, {"order_by" => {"i18n_l" => "name"}})->gather();
$session->disconnect();

foreach my $locale (@$locales) {
	my $ses = OpenSRF::AppSession->create("open-ils.actor");
	$ses->session_locale($locale->code);
	my $tree = $ses->request("open-ils.actor.org_tree.retrieve")->gather(1);

	my $aout = $ses->request("open-ils.actor.org_types.retrieve")->gather(1);
	foreach my $type (@$aout) {
		$types[int($type->id)] = $type;
	}
	my $dir = File::Spec->catdir($path, $locale->code);
	if (!-d $dir) {
		mkdir($dir) or die "Could not create output directory: $dir $!\n";
	}

	my @org_tree_html;
	print_option($tree, \@org_tree_html);
	$ses->disconnect();
	open(FILE, '>', File::Spec->catfile($dir, $filename)) or die $!;
	print FILE @org_tree_html;
	close FILE;
}

sub print_option {
	my $node = shift;
	my $org_tree_html = shift;

	return unless ($node->opac_visible =~ /^[y1t]+/i);

	my $depth = $types[$node->ou_type]->depth;
	my $sname = OpenILS::Application::AppUtils->entityize($node->shortname);
	my $name = OpenILS::Application::AppUtils->entityize($node->name);
	my $kids = $node->children;

	push @$org_tree_html, "<option value='$sname'>" . '&#160;&#160;&#160;'x$depth . "$name</option>\n";
	print_option($_, $org_tree_html) for (@$kids);
}

