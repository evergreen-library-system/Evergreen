#!/usr/bin/perl
# -----------------------------------------------------------------------
# Copyright (C) 2008  Laurentian University
# Dan Scott <dscott@laurentian.ca>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# -----------------------------------------------------------------------

# calculate the proximity of organizations in the organization tree

# vim:noet:ts=4:sw=4

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;

die "usage: perl org_tree_proximity.pl <bootstrap_config>" unless $ARGV[0];
OpenSRF::System->bootstrap_client(config_file => $ARGV[0]);

Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $ses = OpenSRF::AppSession->create("open-ils.storage");
my $result = $ses->request("open-ils.storage.actor.org_unit.refresh_proximity");

if ($result) {
	print "Successfully updated the organization proximity";
} else {
	print "Failed to update the organiziation proximity";
}

$ses->disconnect();
