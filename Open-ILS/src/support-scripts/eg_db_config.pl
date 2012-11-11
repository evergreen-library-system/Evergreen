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
use DBI;
use Cwd qw/abs_path getcwd/;

my ($dbhost, $dbport, $dbname, $dbuser, $dbpw, $help, $admin_user, $admin_pw, $load_all, $load_concerto);
my $config_file = '';
my $build_db_sh = '';
my $offline_file = '';
my $prefix = '';
my $sysconfdir = '';
my $pg_contribdir = '';
my $create_db_sql_contribs = '';
my $create_db_sql_extensions = '';
my @services;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

my $cwd = getcwd();

# Get the directory for this script
my $script_dir = abs_path(dirname($0));

# Set the location and base file for sample data
my $_sample_dir = abs_path(File::Spec->catdir($script_dir, '../../tests/datasets/sql/'));
my $_sample_all = 'load_all.sql';
my $_sample_concerto = 'load_concerto.sql';

=over

=item update_config() - Puts command line specified settings into xml file
=cut
sub update_config {
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

=item create_offline_config() - Write out the offline config
=cut
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

=item get_settings() - Extracts database settings from opensrf.xml
=cut
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

=item create_database() - Creates the database using create_database_contribs.sql
=cut
sub create_database {
	my $settings = shift;

	$ENV{'PGUSER'} = $settings->{user};
	$ENV{'PGPASSWORD'} = $settings->{pw};
	$ENV{'PGPORT'} = $settings->{port};
	$ENV{'PGHOST'} = $settings->{host};
	my @temp = `psql -d postgres -qtc 'show server_version;' | xargs | cut -c1,3`;
	chomp $temp[0];
	my $pgversion = $temp[0];
	my $cmd;
	# If it looks like it is 9.1 or greater, use create_database_extensions.sql
	# Otherwise use create_database_contribs.sql
	if($pgversion >= '91') {
		$cmd = 'psql -vdb_name=' . $settings->{db} . ' -d postgres -f ' . $create_db_sql_extensions;
	} else {
		$cmd = 'psql -vdb_name=' . $settings->{db} . ' -vcontrib_dir=' . $pg_contribdir .
			' -d postgres -f ' . $create_db_sql_contribs;
	}
	my @output = `$cmd 2>&1`;
	if(grep(/(ERROR|No such file or directory)/,@output)) {
		push(@output, "\n------------------------------------------------------------------------------\n",
			"There was a problem creating the database.\n",
			"See above for more information.\n");
		if(grep/unsupported language/, @output) {
			push(@output, "\nYou may need to install the postgresql plperl package on the database server.\n");
		}
		if(grep/No such file or directory/, @output) {
			if($pgversion >= '91') {
				push(@output, "\nYou may need to install the postgresql contrib package on the database server.\n"); 
			} else {
				push(@output, "\nYou may need to install the postgresql contrib package on this server.\n");
			}
		}
		push(@output, "------------------------------------------------------------------------------\n");
		die(@output);
	}
}

=item create_schema() - Creates the database schema by calling build-db.sh
=cut
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

=item load_sample_data() - Loads sample bib records, copies, users, and transactions
=cut
sub load_sample_data {
	my $settings = shift;

	my $load_script = $_sample_all;
	chdir($_sample_dir);
	if ($load_concerto) {
		$load_script = $_sample_concerto;
	}
	$ENV{'PGUSER'} = $settings->{user};
	$ENV{'PGPASSWORD'} = $settings->{pw};
	$ENV{'PGPORT'} = $settings->{port};
	$ENV{'PGHOST'} = $settings->{host};
	$ENV{'PGDATABASE'} = $settings->{db};
	my @output = `psql -f $load_script 2>&1`;
	print @output;
	chdir($cwd);
}

=item set_admin_account() - Sets the administrative user's user name and password
=cut
sub set_admin_account {
	my $admin_user = shift;
	my $admin_pw = shift;
	my $settings = shift;

	my $dbh = DBI->connect('dbi:Pg:dbname=' . $settings->{db} . 
		';host=' . $settings->{host} . ';port=' . $settings->{port} . ';',
		 $settings->{user} . "", $settings->{pw} . "", {AutoCommit => 1}
	);
	if ($dbh->err) {
		print STDERR "Could not connect to database to set admin account. ";
		print STDERR "Error was " . $dbh->errstr . "\n";
		return;
	}
	my $stmt = $dbh->prepare("UPDATE actor.usr SET usrname = ?, passwd = ? WHERE id = 1");
	$stmt->execute(($admin_user, $admin_pw));
	if ($dbh->err) {
		print STDERR "Failed to set admin account. ";
		print STDERR "Error was " . $dbh->errstr . "\n";
		return;
	}
}

my $offline;
my $cdatabase;
my $cschema;
my $uconfig;
my $pgconfig;
my %settings;

GetOptions("create-schema" => \$cschema, 
		"create-database" => \$cdatabase,
		"load-all-sample" => \$load_all,
		"load-concerto-sample" => \$load_concerto,
		"create-offline" => \$offline,
		"update-config" => \$uconfig,
		"config-file=s" => \$config_file,
		"build-db-file=s" => \$build_db_sh,
		"pg-contrib-dir=s" => \$pg_contribdir,
		"create-db-sql-contribs=s" => \$create_db_sql_contribs,
		"create-db-sql-extensions=s" => \$create_db_sql_extensions,
		"pg-config=s" => \$pgconfig,
		"admin-user=s" => \$admin_user,
		"admin-password=s" => \$admin_pw,
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

if (!$pg_contribdir) {
	$pgconfig = 'pg_config' if(!$pgconfig);
	my @temp = `$pgconfig --sharedir`;
	chomp $temp[0];
	$pg_contribdir = File::Spec->catdir($temp[0], 'contrib');
}

if (!$create_db_sql_contribs) {
	$create_db_sql_contribs = File::Spec->catfile($script_dir, '../sql/Pg/create_database_contribs.sql');
}

if (!$create_db_sql_extensions) {
	$create_db_sql_extensions = File::Spec->catfile($script_dir, '../sql/Pg/create_database_extensions.sql');
}

if (!$offline_file) {
	$offline_file = File::Spec->catfile($sysconfdir, 'offline-config.pl');
}

unless (-e $build_db_sh) { die "Error: $build_db_sh does not exist. \n"; }
unless (-e $config_file) { die "Error: $config_file does not exist. \n"; }

if ($uconfig) { update_config(\@services, \%settings); }

# Get our settings from the config file
get_settings(\%settings);

if ($cdatabase) { create_database(\%settings); }
if ($cschema) { create_schema(\%settings); }
if ($admin_user && $admin_pw) {
	set_admin_account($admin_user, $admin_pw, \%settings);
}
if ($load_all || $load_concerto) {
	load_sample_data(\%settings);
}
if ($offline) { create_offline_config($offline_file, \%settings); }

if ((!$cdatabase && !$cschema && !$load_all && !$load_concerto && !$uconfig && !$offline && !$admin_pw) || $help) {
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

    --create-offline
        Creates the database setting file required by the offline data uploader

    --create-schema
        Creates the Evergreen database schema according to the settings in
        the file specified by --config-file.  

    --create-database
        Creates the database itself, provided the user and password options
        represent a superuser.

    --load-all-sample
		Loads all sample data, including bibliographic records, call numbers,
		copies, users, and transactions.

    --load-concerto-sample
		Loads a subset of sample data that includes just 100 bibliographic
		records, and associated call numbers and copies.

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

    --admin-user      administration user's user name

    --admin-pass      administration user's password

EXAMPLES
   This script is normally used during the initial installation and
   configuration process. This creates the database schema, sets
   the administration user's user name and password, and modifies your
   configuration files to include the correct database connection
   information.

   For a single server install, or an install with one web/application
   server and one database server, you will typically want to invoke this
   script with a complete set of commands:

   perl Open-ILS/src/support-scripts/eg_db_config.pl --update-config \
       --service all --create-schema --create-offline \
       --user <db-user> --password <db-pass> --hostname localhost --port 5432 \
       --database evergreen --admin-user <admin-user> --admin-pass <admin-pass> 

   To update the configuration for a single service - for example, if you
   replicated a database for reporting purposes - just issue the
   --update-config command with the service identified and the changed
   database parameters specified:

   perl Open-ILS/src/support-scripts/eg_db_config.pl --update-config \
       --service reporter --hostname foobar --password newpass

HERE
}
