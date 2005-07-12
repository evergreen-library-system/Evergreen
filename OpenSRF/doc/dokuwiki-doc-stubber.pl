#!/usr/bin/perl -w
use OpenSRF::System qw(/pines/conf/bootstrap.conf);
use Getopt::Long

$| = 1;

my $cvs_base = 'http://open-ils.org/cgi-bin/viewcvs.cgi/ILS/Open-ILS/src/perlmods/';
my $nest = 0;
my $service;
my $filter;
my $sort_ignore;

GetOptions(	'cvs_base=s'	=> \$cvs_base,
		'nest'		=> \$nest,
		'service=s'	=> \$service,
		'ignore=s'	=> \$sort_ignore,
		'filter=s'	=> \$filter,
);

unless( $service ) {
	print "usage: $0 -s <service name> [-c <cvs repo base URL> -f <regex filter for method names> -n]\n";
	exit;
}

OpenSRF::System->bootstrap_client();
my $session = OpenSRF::AppSession->create( $service );

my $req; 
if ($filter) {
	$req = $session->request('opensrf.system.method', $filter);
} else {
	$req = $session->request('opensrf.system.method.all');
}

my $count = 1;
my %m;
while( my $meth = $req->recv(60) ) {
	$meth = $meth->content;

	$api_name = $meth->{api_name};

	$m{$api_name}{api_name} = $meth->{api_name};

	$m{$api_name}{package} = $meth->{package};
	$m{$api_name}{method} = $meth->{method};

	$m{$api_name}{api_level} = int $meth->{api_level};
	$m{$api_name}{server_class} = $meth->{server_class} || '**ALL**';
	$m{$api_name}{stream} = int($meth->{stream} || 0);
	$m{$api_name}{cachable} = int($meth->{cachable} || 0);

	$m{$api_name}{note} = $meth->{note} || 'what I do';
	($m{$api_name}{cvs} = $m{$api_name}{package}) =~ s/::/\//go;

	$m{$api_name}{stream} = $m{$api_name}{stream}?'Yes':'No';
	$m{$api_name}{cachable} = $m{$api_name}{cachable}?'Yes':'No';

	print STDERR "." unless ($count % 10);

	$count++;
}

warn "\nThere are ".scalar(keys %m)." methods published by $service\n";

my @m_list;
if (!$sort_ignore) {
	@m_list = sort keys %m;
} else {
	@m_list =
		map { ($$_[0]) }
		sort {
		  	$$a[1] cmp $$b[1]
				||
			length($$b[0]) <=> length($$a[0])
		} map {
			[$_ =>
			do {
				(my $x = $_) =~ s/^$sort_ignore//go;
				$x;
			} ]
		} keys %m;
}

for my $meth ( @m_list ) {

	my $pad = 0;
	my $header = '=====';
	if ($nest) {
		no warnings;
		(my $x = $meth) =~ s/\./$pad++;$1/eg;
	}
	$pad = ' 'x$pad;

	print <<"	METHOD";
$pad$header $meth $header

$m{$meth}{note}

  * [[osrf-devel:terms#opensrf_api-level|API Level]]: $m{$meth}{api_level}
  * [[osrf-devel:terms#opensrf_server_class|Server Class]]: $m{$meth}{server_class}
  * Implementation Method: [[$cvs_base/$m{$meth}{cvs}.pm|$m{$meth}{package}\::$m{$meth}{method}]]
  * Streaming [[osrf-devel:terms#opensrf_method|Method]]: $m{$meth}{stream}
  * Cachable [[osrf-devel:terms#opensrf_method|Method]]: $m{$meth}{cachable}

  * **Parameters:**
    * //param1//\\\\ what it is...
  * **Returns:**
    * //Success//\\\\ successful format
    * //Failure//\\\\ failure format (exception, etc)


	METHOD
}

