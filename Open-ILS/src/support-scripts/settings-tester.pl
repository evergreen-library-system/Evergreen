#!/usr/bin/perl
# vim:noet:ts=4:
use strict;
use warnings;

BEGIN {
	eval "use OpenSRF::Utils::Config;";
	die "Please ensure that /openils/lib/perl5 is in your PERL5LIB environment variable.
	You must run this script as the 'opensrf' user.\n" if ($@);
	eval "use Error qw/:try/;";
	die "Please install Error.pm.\n" if ($@);
	eval "use UNIVERSAL::require;";
	die "Please install the UNIVERSAL::require perl module.\n" if ($@);
	eval "use Getopt::Long;";
	die "Please install the Getopt::Long perl module.\n" if ($@);
	eval "use Net::Domain;";
	die "Please install the Net::Domain perl module.\n" if ($@);
}

my $output = '';
my $perloutput = '';
my $result;

my ($gather, $hostname, $core_config, $tmpdir) =
	(0, Net::Domain::hostfqdn(), '/openils/conf/opensrf_core.xml', '/tmp/');

GetOptions(
	'gather' => \$gather,
	'hostname=s' => \$hostname,
	'config_file=s' => \$core_config,
	'tempdir=s' => \$tmpdir,
);

while (my $mod = <DATA>) {
	chomp $mod;
	my @list = split / /, $mod;

	my $ok = 0;
	for my $m (@list) {
		if ($m->use) {
			$ok++;
			my $version = $m->VERSION;
			print "$m version $version\n" if ($version);
		}
	}

	unless ($ok) {
		if (@list == 1) {
			warn "Please install $mod\n";
			$perloutput .= "Please install the $mod Perl module.\n";
		} else {
			warn "Please install one of the following modules: $mod\n";
			$perloutput .= "Please install one of the following modules: $mod\n";
		}
	}
			
}

use OpenSRF::Transport::SlimJabber::Client;
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::SettingsClient;
use Data::Dumper;
use DBI;

(my $conf_dir = $core_config) =~ s#(.*)/.*#$1#;


OpenSRF::Utils::Config->load(config_file => $core_config);
my $conf = OpenSRF::Utils::Config->current;
my $j_username    = $conf->bootstrap->username;
my $j_password    = $conf->bootstrap->passwd;
my $j_port    = $conf->bootstrap->port;
# We should check for a domains element to catch likely upgrade errors
my $j_domain    = $conf->bootstrap->domain;
my $settings_config = $conf->bootstrap->settings_config;
my $logfile    = $conf->bootstrap->logfile;
(my $log_dir = $logfile) =~ s#(.*)/.*#$1#;


print "\nChecking Jabber connection\n";
# connect to jabber 
my $client = OpenSRF::Transport::SlimJabber::Client->new(
    port => $j_port, 
    username => $j_username, 
    password => $j_password,
    host => $j_domain,
    resource => 'test123'
);


my $je = undef;
try {
    unless($client->initialize()) {
        $je = "* Unable to connect to jabber server $j_domain\n";
        warn "* Unable to connect to jabber server $j_domain\n";
    }
} catch Error with {
    $je = "* Error connecting to jabber:\n" . shift() . "\n";
    warn "* Error connecting to jabber:\n" . shift() . "\n";
};

print "* Jabber successfully connected\n" unless ($je);
$output .= ($je) ? $je : "* Jabber successfully connected\n";

my $xmlparser = XML::LibXML->new();
my $osrfxml = $xmlparser->parse_file($settings_config);

print "\nChecking database connections\n";
# Check database connections
my @databases = $osrfxml->findnodes('//database');
foreach my $database (@databases) {
	my $db_name = $database->findvalue("./db");	
	if (!$db_name) {
		$db_name = $database->findvalue("./name");	
	}
	my $db_host = $database->findvalue("./host");	
	my $db_port = $database->findvalue("./port");	
	my $db_user = $database->findvalue("./user");	
	my $db_pw = $database->findvalue("./pw");	
    if (!$db_pw && $database->parentNode->parentNode->nodeName eq 'reporter') {
        $db_pw = $database->findvalue("./password");
        warn "* WARNING: Deprecated <password> element used for the <reporter> entry.  ".
            "Please use <pw> instead.\n" if ($db_pw);
    }

	my $osrf_xpath;
	foreach my $node ($database->findnodes("ancestor::node()")) {
		next unless $node->nodeType == XML::LibXML::XML_ELEMENT_NODE;
		$osrf_xpath .= "/" . $node->nodeName;
	}
	$output .= test_db_connect($db_name, $db_host, $db_port, $db_user, $db_pw, $osrf_xpath);
}

print "\nChecking database drivers to ensure <driver> matches <language>\n";
# Check database drivers
# if language eq 'C', driver eq 'pgsql'
# if language eq 'perl', driver eq 'Pg'
my @drivers = $osrfxml->findnodes('//driver');
foreach my $driver_node (@drivers) {
	my $language;
	my $driver_xpath;
	my @driver_xpath_nodes;
	foreach my $node ($driver_node->findnodes("ancestor::node()")) {
		next unless $node->nodeType == XML::LibXML::XML_ELEMENT_NODE;
		$driver_xpath .= "/" . $node->nodeName;
		push @driver_xpath_nodes, $node->nodeName;
	}
	my $lang_xpath;
	my $driver = $driver_node->findvalue("child::text()");
	while (pop(@driver_xpath_nodes) && scalar(@driver_xpath_nodes) > 0 && !$language) {
		$lang_xpath = "/" . join('/', @driver_xpath_nodes) . "/language";
		my @lang_nodes = $osrfxml->findnodes($lang_xpath);
		next unless scalar(@lang_nodes > 0);
		$language = $lang_nodes[0]->findvalue("child::text()");
	}
	if ($driver eq "pgsql") {
		if ($driver_xpath =~ m#/reporter/#) {
			$result = "* ERROR: reporter application must use driver 'Pg', but '$driver' is defined\n";
			warn $result;
		} elsif ($language eq "C") {
			$result = "* OK: $driver language is $language in $lang_xpath\n";
		} else {
			$result = "* ERROR: $driver language is $language in $lang_xpath\n";
			warn $result;
		}
	} elsif ($driver eq "Pg") {
		if ($driver_xpath =~ m#/reporter/#) {
			$result = "* OK: $driver language is undefined for reporter base configuration\n";
		} elsif ($language eq "perl") {
			$result = "* OK: $driver language is $language in $lang_xpath\n";
		} else {
			$result = "* ERROR: $driver language is $language in $lang_xpath\n";
			warn $result;
		}
	} else {
		$result = "* ERROR: Unknown driver $driver in $driver_xpath\n";
		warn $result;
	}
	print $result;
	$output .= $result;
}

print "\nChecking libdbi and libdbi-drivers\n";
$output .= check_libdbd();

print "\nChecking hostname\n";
my @hosts = $osrfxml->findnodes('/opensrf/hosts/*');
foreach my $host (@hosts) {
	next unless $host->nodeType == XML::LibXML::XML_ELEMENT_NODE;
	my $osrfhost = $host->nodeName;
	my $he;
	if ($osrfhost ne $hostname && $osrfhost ne "localhost") {
		$result = " * ERROR: expected hostname '$hostname', found '$osrfhost' in <hosts> section of opensrf.xml\n";
		warn $result;
		$he = 1;
	} elsif ($osrfhost eq "localhost") {
		$result = " * OK: found hostname 'localhost' in <hosts> section of opensrf.xml\n";
	} else {
		$result = " * OK: found hostname '$hostname' in <hosts> section of opensrf.xml\n";
	}
	print $result unless $he;
	$output .= $result;
}


if ($gather) {
	get_debug_info( $tmpdir, $log_dir, $conf_dir, $perloutput, $output );
}

sub test_db_connect {
	my ($db_name, $db_host, $db_port, $db_user, $db_pw, $osrf_xpath) = @_;

	my $dsn = "dbi:Pg:dbname=$db_name;host=$db_host;port=$db_port";
	my $de = undef;
	my ($dbh, $encoding);
	try {
		$dbh = DBI->connect($dsn, $db_user, $db_pw);
		unless($dbh) {
			$de = "* $osrf_xpath :: Unable to connect to database $dsn, user=$db_user, password=$db_pw\n";
			warn "* $osrf_xpath :: Unable to connect to database $dsn, user=$db_user, password=$db_pw\n";
		}
		my $sth = $dbh->prepare("show server_encoding");
		$sth->execute;
		$sth->bind_col(1, \$encoding);
		$sth->fetch;
		$sth->finish;
		$dbh->disconnect;
	} catch Error with {
		$de = "* $osrf_xpath :: Unable to connect to database $dsn, user=$db_user, password=$db_pw\n" . shift() . "\n";
		warn "* $osrf_xpath :: Unable to connect to database $dsn, user=$db_user, password=$db_pw\n" . shift() . "\n";
	};
	print "* $osrf_xpath :: Successfully connected to database $dsn\n" unless ($de);
	if ($encoding !~ m/(utf-?8|unicode)/i) {
		$de .= "* ERROR: $osrf_xpath :: Database $dsn has encoding $encoding instead of UTF8 or UNICODE.\n";
		warn "* ERROR: $osrf_xpath :: Database $dsn has encoding $encoding instead of UTF8 or UNICODE.\n";
	} else {
		print "  * Database has the expected server encoding $encoding.\n";
	}
	return ($de) ? $de : "* $osrf_xpath :: Successfully connected to database $dsn with encoding $encoding\n";

}

sub check_libdbd {
	my $results = '';
	my @location = `locate libdbdpgsql.so | grep -v home | grep -v .libs`; # simple(ton) attempt to filter out build versions
    unless(@location) {
        my $res = "Libdbi postgres driver not found\n";
        print $res;
        return $res;
    }
	if (scalar(@location) > 1) {

		my $res = "Found more than one location for libdbdpgsql.so.
  We have found that system packages don't link against libdbi.so;
  therefore, we strongly recommend compiling libdbi and libdbi-drivers from source.\n";
		$results .= $res;
		print $res;
	}
	foreach my $loc (@location) {
		my @linkage = `ldd $loc`;
		if (!grep(/libdbi/, @linkage)) {
			my $res = "$loc was not linked against libdbi - you probably need to compile libdbi-drivers from source with the --enable-libdbi configure switch.\n";
			$results .= $res;
			print $res;
		}
	}
	return $results;
}

sub get_debug_info {
  my $temp_dir = shift; # place we can write files
  my $log = shift; # location of the log directory
  my $config = shift; # location of the config files
  my $perl_test = shift; # output from the Perl prereq testing
  my $config_test = shift; # output from the config file testing

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $oils_time = sprintf("%04d-%02d-%02d_%02dh-%02d-%02d", $year+1900, $mon, $mday, $hour, $min, $sec);
  
  # evil approach that requires no other Perl dependencies
  chdir($temp_dir);
  my $oils_debug_dir = "$temp_dir/oils_$oils_time";

  # Replace with something Perlish
  mkdir($oils_debug_dir) or die $!;

  # Replace with File::Copy
  system("cp $log/*log $oils_debug_dir");

  # Passwords will go through in the clear for now
  system("cp $config/*xml $oils_debug_dir");

  # Get Perl output
  open(FH, ">", "$oils_debug_dir/perl_test.out") or die $!;
  print FH $perl_test;
  close(FH);

  # Get XML output
  open(FH, ">", "$oils_debug_dir/xml_test.out") or die $!;
  print FH $config_test;
  close(FH);
  
  # Tar this up - does any system not have tar?
  system("tar czf oils_$oils_time.tar.gz oils_$oils_time");

  # Clean up after ourselves, somewhat dangerously
  system("rm -fr $oils_debug_dir");

  print "Wrote your debug information to $temp_dir/oils_$oils_time.tar.gz.\n";
}

__DATA__
LWP::UserAgent
XML::LibXML
XML::LibXML::XPathContext
XML::LibXSLT
Net::Server::PreFork
Cache::Memcached
Class::DBI
Class::DBI::AbstractSearch
Template
DBD::Pg
Net::Z3950 Net::Z3950::ZOOM
MARC::Record
MARC::Charset
MARC::File::XML
Text::Aspell
CGI
DateTime::TimeZone
DateTime
DateTime::Format::ISO8601
Unix::Syslog
GD::Graph3d
JavaScript::SpiderMonkey
Log::Log4perl
Email::Send
Text::CSV
Text::CSV_XS
Spreadsheet::WriteExcel::Big
Tie::IxHash
Parse::RecDescent
SRU
