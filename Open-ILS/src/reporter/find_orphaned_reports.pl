#!/usr/bin/perl -w

use DBI;
use Getopt::Long;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils qw/:daemon/;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Reporter::SQLBuilder;
use File::Find;

my ($config, $du, $live, %seen) = ('SYSCONFDIR/bootstrap.conf', 0, 0);

GetOptions(
	"boostrap=s"	=> \$config,
	"du"	=> \$du,
	"live"	=> \$live,
);

OpenSRF::System->bootstrap_client( config_file => $config );

my $sc = OpenSRF::Utils::SettingsClient->new;
my $db_driver = $sc->config_value( reporter => setup => database => 'driver' );
my $db_host = $sc->config_value( reporter => setup => database => 'host' );
my $db_port = $sc->config_value( reporter => setup => database => 'port' );
my $db_name = $sc->config_value( reporter => setup => database => 'name' );
my $db_user = $sc->config_value( reporter => setup => database => 'user' );
my $db_pw = $sc->config_value( reporter => setup => database => 'password' );

my $output_base = $sc->config_value( reporter => setup => files => 'output_base' );

my $dsn = "dbi:" . $db_driver . ":dbname=" . $db_name .';host=' . $db_host . ';port=' . $db_port;

my $dbh = DBI->connect($dsn,$db_user,$db_pw, {pg_enable_utf8 => 1, RaiseError => 1});

find(\&wanted, $output_base);

$dbh->disconnect;


sub wanted {
	my $dir = $File::Find::dir;
	$dir =~ s/^$output_base//;
	$dir =~ s#^/+##;
	$dir =~ s#/+$##;
	my @list = split '/', $dir;
	return unless @list == 3;
	return if $seen{$list[2]};
	$seen{$list[2]} = 1;

	if ($dbh->selectrow_array("SELECT id FROM reporter.schedule WHERE id = $list[2];")) {
		print STDERR "$output_base/" . join('/', @list) . ( $du ? "\0" : "\n" ) if ($live);
	} else {
		print "$output_base/" . join('/', @list) . ( $du ? "\0" : "\n" );
	}

	if ($dbh->selectrow_array("SELECT id FROM reporter.report WHERE id = $list[1];")) {
		print STDERR "$output_base/" . join('/', @list[0,1]) . ( $du ? "\0" : "\n" ) if ($live);
	} else {
		print "$output_base/" . join('/', @list[0,1]) . ( $du ? "\0" : "\n" );
	}

	if ($dbh->selectrow_array("SELECT id FROM reporter.template WHERE id = $list[0];")) {
		print STDERR "$output_base/" . $list[0] . ( $du ? "\0" : "\n" ) if ($live);
	} else {
		print "$output_base/" . $list[0] . ( $du ? "\0" : "\n" );
	}
}


