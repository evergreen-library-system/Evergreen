#!/usr/bin/perl
# eg_db_config.pl -- configure Evergreen database settings and create schema
# vim:noet:ts=4:sw=4:
#
# Copyright (C) 2008 Equinox Software, Inc.
# Copyright (C) 2008-2009 Laurentian University
# Author: Kevin Beswick <kevinbeswick00@gmail.com>
# Author: Dan Scott <dscott@laurentian.ca>
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

use strict; use warnings;
use XML::LibXML;
use File::Copy;
use Getopt::Long;
use File::Spec;
use File::Basename;

my ($dbhost, $dbport, $dbname, $dbuser, $dbpw, $help);
my $config_file = '';
my $build_db_sh = '';
my $bootstrap_file = '';
my $offline_file = '';
my $prefix = '';
my $sysconfdir = '';
my @services;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

# Get the directory for this script
my $script_dir = dirname($0);

sub update_config {
	# Puts command line specified settings into xml file
	my ($services, $settings) = @_;

	my $parser = XML::LibXML->new();
	my $opensrf_config = $parser->parse_file($config_file);

	if (@$services) {
		foreach my $service (@$services) {
			foreach my $key (keys %$settings) {
				next unless $settings->{$key};
				my @node;

				if ($service eq 'state_store') {
					(@node) = $opensrf_config->findnodes("//state_store/$key/text()");
				} else {
					(@node) = $opensrf_config->findnodes("//$service//database/$key/text()");
				}

				foreach (@node) {
					$_->setData($settings->{$key});
				}
			}

		}
	}

	my $timestamp = sprintf("%d.%d.%d.%d.%d.%d",
		$year + 1900, $mon +1, $mday, $hour, $min, $sec);
	if (copy($config_file, "$config_file.$timestamp")) {
		print "Backed up original configuration file to '$config_file.$timestamp'\n";
	} else {
		print STDERR "Unable to write to '$config_file.$timestamp'; bailed out.\n";
	}

	$opensrf_config->toFile($config_file) or
		die "ERROR: Failed to update the configuration file '$config_file'\n";
}

# write out the DB bootstrapping config
sub create_db_bootstrap {
	my ($setup, $settings) = @_;

	open(FH, '>', $setup) or die "Could not write database setup to $setup\n";

	print "Writing database bootstrapping configuration to $setup\n";

	printf FH "\$main::config{dsn} = 'dbi:Pg:host=%s;dbname=%s;port=%d';\n",
		$settings->{host}, $settings->{db}, $settings->{port};

	printf FH "\$main::config{usr} = '%s';\n", $settings->{user};
	printf FH "\$main::config{pw} = '%s';\n", $settings->{pw};
	
	print FH "\$main::config{index} = 'config.cgi';\n";
	close(FH);
}

# write out the offline config
sub create_offline_config {
	my ($setup, $settings) = @_;

	open(FH, '>', $setup) or die "Could not write offline database setup to $setup\n";

	print "Writing offline database configuration to $setup\n";

	printf FH "\$main::config{base_dir} = '%s/var/data/offline/';\n", $prefix;
	printf FH "\$main::config{bootstrap} = '%s/opensrf_core.xml';\n", $sysconfdir;

	printf FH "\$main::config{dsn} = 'dbi:Pg:host=%s;dbname=%s;port=%d';\n",
		$settings->{host}, $settings->{db}, $settings->{port};

	printf FH "\$main::config{usr} = '%s';\n", $settings->{user};
	printf FH "\$main::config{pw} = '%s';\n", $settings->{pw};

	close(FH);
}
# Extracts database settings from opensrf.xml
sub get_settings {
	my $settings = shift;

	my $host = "/opensrf/default/apps/open-ils.storage/app_settings/databases/database/host/text()";
	my $port = "/opensrf/default/apps/open-ils.storage/app_settings/databases/database/port/text()";
	my $dbname = "/opensrf/default/apps/open-ils.storage/app_settings/databases/database/db/text()";
	my $user = "/opensrf/default/apps/open-ils.storage/app_settings/databases/database/user/text()";
	my $pw = "/opensrf/default/apps/open-ils.storage/app_settings/databases/database/pw/text()";

	my $parser = XML::LibXML->new();
	my $opensrf_config = $parser->parse_file($config_file);

	# If the user passed in settings at the command line,
	# we don't want to override them
	$settings->{host} = $settings->{host} || $opensrf_config->findnodes($host);
	$settings->{port} = $settings->{port} || $opensrf_config->findnodes($port);
	$settings->{db} = $settings->{db} || $opensrf_config->findnodes($dbname);
	$settings->{user} = $settings->{user} || $opensrf_config->findnodes($user);
	$settings->{pw} = $settings->{pw} || $opensrf_config->findnodes($pw);
}

# Creates the database schema by calling build-db.sh
sub create_schema {
	my $settings = shift;

	chdir(dirname($build_db_sh));
	my $cmd = File::Spec->catfile('.', basename($build_db_sh)) . " " .
		$settings->{host} ." ".  $settings->{port} ." ". 
		$settings->{db} ." ".  $settings->{user} ." ". 
		$settings->{pw};
	system($cmd);
	chdir($script_dir);
}

my $bootstrap;
my $offline;
my $cschema;
my $uconfig;
my %settings;

GetOptions("create-schema" => \$cschema, 
		"create-bootstrap" => \$bootstrap,
		"create-offline" => \$offline,
		"update-config" => \$uconfig,
		"bootstrap-file=s" => \$bootstrap_file,
		"config-file=s" => \$config_file,
		"build-db-file=s" => \$build_db_sh,
		"service=s" => \@services,
		"user=s" => \$settings{'user'},
		"password=s" => \$settings{'pw'},
		"database=s" => \$settings{'db'},
		"hostname=s" => \$settings{'host'},
		"port=i" => \$settings{'port'}, 
		"help" => \$help
);

if (grep(/^all$/, @services)) {
	@services = qw/reporter open-ils.cstore open-ils.pcrud open-ils.storage open-ils.reporter-store state_store/;
}

my $eg_config = File::Spec->catfile($script_dir, '../extras/eg_config');

if (!$config_file) { 
	my @temp = `$eg_config --sysconfdir`;
	chomp $temp[0];
	$sysconfdir = $temp[0];
	$config_file = File::Spec->catfile($sysconfdir, "opensrf.xml");
}

if (!$prefix) {
	my @temp = `$eg_config --prefix`;
	chomp $temp[0];
	$prefix = $temp[0];
}

if (!$build_db_sh) {
	$build_db_sh = File::Spec->catfile($script_dir, '../sql/Pg/build-db.sh');
}

if (!$bootstrap_file) {
	$bootstrap_file = File::Spec->catfile($sysconfdir, 'live-db-setup.pl');
}

if (!$offline_file) {
	$offline_file = File::Spec->catfile($sysconfdir, 'offline-config.pl');
}

unless (-e $build_db_sh) { die "Error: $build_db_sh does not exist. \n"; }
unless (-e $config_file) { die "Error: $config_file does not exist. \n"; }

if ($uconfig) { update_config(\@services, \%settings); }

# Get our settings from the config file
get_settings(\%settings);

if ($cschema) { create_schema(\%settings); }
if ($bootstrap) { create_db_bootstrap($bootstrap_file, \%settings); }
if ($offline) { create_offline_config($offline_file, \%settings); }

if ((!$cschema && !$uconfig && !$bootstrap && !$offline) || $help) {
	print <<HERE;

SYNOPSIS
    eg_db_config.pl [OPTION] ... [COMMAND] ... [CONFIG OPTIONS]

DESCRIPTION
    Creates or recreates the Evergreen database schema based on the settings
    in the opensrf.xml configuration file.

    Manipulates the configuration file 

OPTIONS
    --config-file
        specifies the opensrf.xml file. Defaults to /openils/conf/opensrf.xml

    --bootstrap-file
        specifies the database bootstrap file required by the CGI setup
        interface. Defaults to /openils/conf/live-db-setup.pl

    --build-db-file
        specifies the script that creates the database schema. Defaults to
        Open-ILS/src/sql/pg/build-db.sh

    --offline-file
        specifies the offline database settings file required by the offline
        data uploader. Defaults to /openils/conf/offline-config.pl

COMMANDS
    --update-config
        Configures Evergreen database settings in the file specified by
        --build-db-file.  

    --create-bootstrap
        Creates the database bootstrap file required by the CGI setup interface

    --create-offline
        Creates the database setting file required by the offline data uploader

    --create-schema
        Creates the Evergreen database schema according to the settings in
        the file specified by --config-file.  

SERVICE OPTIONS
    --service
        Specify "all" or one or more of the following services to update:
            * reporter
            * open-ils.cstore
            * open-ils.pcrud
            * open-ils.storage
            * open-ils.reporter-store
            * state_store
    
DATABASE CONFIGURATION OPTIONS
    --user            username for the database 

    --password        password for the user 

    --database        name of the database 

    --hostname        name or address of the database host 

    --port            port number for database access

EXAMPLES
   This script is normally used during the initial installation and
   configuration process.

   For a single server install, or an install with one web/application
   server and one database server, you will typically want to invoke this
   script with a complete set of commands:

   perl Open-ILS/src/support-scripts/eg_db_config.pl --update-config \
       --service all --create-schema --create-bootstrap --create-offline \
       --user evergreen --password evergreen --hostname localhost --port 5432 \
       --database evergreen 

   To update the configuration for a single service - for example, if you
   replicated a database for reporting purposes - just issue the
   --update-config command with the service identified and the changed
   database parameters specified:

   perl Open-ILS/src/support-scripts/eg_db_config.pl --update-config \
       --service reporter --hostname foobar --password newpass

HERE
}
