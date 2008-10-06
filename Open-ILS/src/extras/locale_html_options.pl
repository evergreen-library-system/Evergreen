#!/usr/bin/perl
use strict;
use warnings;
# Turns supported locales into a static HTML option list

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;

die "usage: perl locale_html_options.pl <bootstrap_config> <output_file>" unless $ARGV[1];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

open FILE, ">$ARGV[1]";

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $ses = OpenSRF::AppSession->create("open-ils.cstore");
my $locales = $ses->request("open-ils.cstore.direct.config.i18n_locale.search.atomic", {"code" => {"!=" => undef}}, {"order_by" => {"i18n_l" => "name"}})->gather();

print_option($locales);

$ses->disconnect();
close FILE;


sub print_option {
	my $locales = shift;
	my $count = 0;
	my $class;
	foreach my $locale (@$locales) {
		my $code = OpenILS::Application::AppUtils->entityize($locale->code);
		my $name = OpenILS::Application::AppUtils->entityize($locale->name);
		if ($count % 2) {
			$class = 'greenrow';
		} else {
			$class = 'bluerow';
		}
		print FILE "<p class='$class'><a href='/opac/$code/extras/slimpac/start.html'>$name</a></p>\n";
		$count++;
	}
}

