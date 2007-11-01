#!/usr/bin/perl
# vim:noet:ts=4:

BEGIN {
	eval "use Error qw/:try/;";
	die "Please install Error.pm!\n" if ($@);
	eval "use UNIVERSAL::require;";
	die "Please install the UNIVERSAL::Require perl module!\n" if ($@);
	eval "use Getopt::Long;";
	die "Please install the Getopt::Long perl module!\n" if ($@);
	eval "use Net::Domain;";
	die "Please install the Net::Domain perl module!\n" if ($@);
}

my $output = '';
my $perloutput = '';

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
	warn "Please install $mod\n" unless ($mod->use);
	$perloutput .= "Please install $mod\n";
	print "$mod version ".${$mod."::VERSION"}."\n" unless ($@);
}

use OpenSRF::Transport::SlimJabber::Client;
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Config;
use Data::Dumper;
use DBI;

(my $conf_dir = $core_config) =~ s#(.*)/.*#$1#;


OpenSRF::Utils::Config->load(config_file => $core_config);
my $conf = OpenSRF::Utils::Config->current;
my $j_username    = $conf->bootstrap->username;
my $j_password    = $conf->bootstrap->passwd;
my $j_port    = $conf->bootstrap->port;
my $j_domain    = $conf->bootstrap->domains->[0];
my $settings_config = $conf->bootstrap->settings_config;
my $logfile    = $conf->bootstrap->logfile;
(my $log_dir = $logfile) =~ s#(.*)/.*#$1#;


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

# parse the opensrf.xml file
my $sparser = 'OpenSRF::Utils::SettingsParser';
my $res = $sparser->initialize($settings_config);
my $sconfig = $sparser->get_server_config($hostname);
my $db_config = $sconfig->{apps}->{'open-ils.storage'}->{app_settings}->{databases}->{database};

# grab the open-ils.storage database settings
my $db_host = $db_config->{host};
my $db_user = $db_config->{user};
my $db_port = $db_config->{port};
my $db_pw = $db_config->{pw};
my $db_db = $db_config->{db};


# connect to the database
my $dsn = "dbi:Pg:dbname=$db_db;host=$db_host;port=$db_port";
my $de = undef;
try {
    unless( DBI->connect($dsn, $db_user, $db_pw) ) {
        $de = "* Unable to connect to database $dsn, user=$db_user, password=$db_pw\n";
        warn "* Unable to connect to database $dsn, user=$db_user, password=$db_pw\n";
    }
} catch Error with {
    $de = "* Unable to connect to database $dsn, user=$db_user, password=$db_pw\n" . shift() . "\n";
    warn "* Unable to connect to database $dsn, user=$db_user, password=$db_pw\n" . shift() . "\n";
};
print "* Successfully connected to database $dsn\n" unless ($de);
$output .= ($de) ? $de : "* Successfully connected to database $dsn\n";

$output .= check_libdbd();

if ($gather) {
	get_debug_info( $tmpdir, $log_dir, $conf_dir, $perloutput, $output );
}

sub check_libdbd {
	my $results;
	my $de = undef;
	my @location = `locate libdbdpgsql.so`;
	if ($location > 1) {

		my $res = "Found more than one location for libdbdpgsql.so.
  We have found that system packages don't link against libdbi.so;
  therefore, we strongly recommend compiling libdbi and libdbi-drivers from source.\n";
		$results .= $res;
		print $res;
	}
	foreach my $loc (@location) {
		my @linkage = `ldd $loc`;
		if (!grep(/libdbi/, @linkage)) {
			my $res = "libdbi.so was not linked against $loc - you probably need to compile from source.\n";
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

  print "Wrote your debug information to oils_$oils_time.tar.gz.\n";
}

__DATA__
LWP::UserAgent
XML::LibXML
XML::LibXSLT
Net::Server::PreFork
Cache::Memcached
Class::DBI
Class::DBI::AbstractSearch
Template
DBD::Pg
Net::Z3950
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
