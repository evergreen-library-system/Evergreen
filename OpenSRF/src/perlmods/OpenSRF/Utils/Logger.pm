package OpenSRF::Utils::Logger;
use strict;
use vars qw($AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Unix::Syslog qw(:macros :subs);
use base qw/OpenSRF Exporter/;
use FileHandle;
use Time::HiRes qw(gettimeofday);
use OpenSRF::Utils::Config;
use Fcntl;

=head1

Logger code

my $logger = OpenSRF::Utils::Logger;
$logger->error( $msg );

For backwards compability, a log level may also be provided to each log
function thereby overriding the level defined by the function.

i.e. $logger->error( $msg, WARN );  # logs at log level WARN

=cut

@EXPORT_OK = qw/ NONE ERROR WARN INFO DEBUG INTERNAL /;

%EXPORT_TAGS = ( level => [ qw/ NONE ERROR WARN INFO DEBUG INTERNAL / ] );

my $config;							# config handle
my $loglevel;						# global log level
my $logfile;						# log file
my $facility;						# syslog facility
my $actfac;							# activity log syslog facility
my $actfile;						# activity log file
my $service = "osrf";			# default service name
my $syslog_enabled = 0;			# is syslog enabled?
my $act_syslog_enabled = 0;	# is syslog enabled?
my $logfile_enabled = 1;		# are we logging to a file?
my $act_logfile_enabled = 1;	# are we logging to a file?
my $logdir;							# log file directory

# log levels
sub ACTIVITY	{ return -1; }
sub NONE			{ return 0;	}
sub ERROR		{ return 1;	}
sub WARN			{ return 2;	}
sub INFO			{ return 3;	}
sub DEBUG		{ return 4;	}
sub INTERNAL	{ return 5;	}
sub ALL			{ return 100; }

# load up our config options
sub set_config {

	return if defined $config;

	$config = OpenSRF::Utils::Config->current;
	if( !defined($config) ) {
		$loglevel = INFO();
		warn "*** Logger found no config.  Using STDERR ***\n";
	}

	$loglevel =  $config->bootstrap->debug; 
	if($loglevel =~ /error/i){ $loglevel = ERROR(); }
	elsif($loglevel =~ /warn/i){ $loglevel = WARN(); }
	elsif($loglevel =~ /info/i){ $loglevel = INFO(); }
	elsif($loglevel =~ /debug/i){ $loglevel = DEBUG(); }
	elsif($loglevel =~ /internal/i){ $loglevel = INTERNAL(); }
	else{$loglevel= INFO(); }

	my $logdir = $config->bootstrap->log_dir;

	$logfile = $config->bootstrap->logfile;
	if($logfile =~ /^syslog/) {
		$syslog_enabled = 1;
		$logfile_enabled = 0;
		$logfile =~ s/^syslog:?//;
		$facility = $logfile;
		$logfile = undef;
		$facility = _fac_to_const($facility);
		openlog($service, 0, $facility);

	} else { $logfile = "$logdir/$logfile"; }

	$actfile = $config->bootstrap->actlog;
	if($actfile =~ /^syslog/) {
		$act_syslog_enabled = 1;
		$act_logfile_enabled = 0;
		$actfile =~ s/^syslog:?//;
		$actfac = $actfile || "local1";
		$actfile = undef;
		$actfac = _fac_to_const($actfac);

	} else { $actfile = "$logdir/$actfile"; }

	#warn "Level: $loglevel, Fac: $facility, Act: $actfac\n";
}

sub _fac_to_const {
	my $name = shift;
	return LOG_LOCAL0 unless $name;
	return LOG_LOCAL0 if $name =~ /local0/i;
	return LOG_LOCAL1 if $name =~ /local1/i;
	return LOG_LOCAL2 if $name =~ /local2/i;
	return LOG_LOCAL3 if $name =~ /local3/i;
	return LOG_LOCAL4 if $name =~ /local4/i;
	return LOG_LOCAL5 if $name =~ /local5/i;
	return LOG_LOCAL6 if $name =~ /local6/i;
	return LOG_LOCAL7 if $name =~ /local7/i;
	return LOG_LOCAL0;
}

sub is_syslog {
	set_config();
	return $syslog_enabled;
}

sub is_act_syslog {
	set_config();
	return $act_syslog_enabled;
}

sub is_filelog {
	set_config();
	return $logfile_enabled;
}

sub is_act_filelog {
	set_config();
	return $act_logfile_enabled;
}

sub set_service {
	my( $self, $svc ) = @_;
	$service = $svc;	
	if( is_syslog() ) {
		closelog();
		openlog($service, 0, $facility);
	}
}

sub error {
	my( $self, $msg, $level ) = @_;
	$level = ERROR() unless defined ($level);
	_log_message( $msg, $level );
}

sub warn {
	my( $self, $msg, $level ) = @_;
	$level = WARN() unless defined ($level);
	_log_message( $msg, $level );
}

sub info {
	my( $self, $msg, $level ) = @_;
	$level = INFO() unless defined ($level);
	_log_message( $msg, $level );
}

sub debug {
	my( $self, $msg, $level ) = @_;
	$level = DEBUG() unless defined ($level);
	_log_message( $msg, $level );
}

sub internal {
	my( $self, $msg, $level ) = @_;
	$level = INTERNAL() unless defined ($level);
	_log_message( $msg, $level );
}

sub activity {
	my( $self, $msg ) = @_;
	_log_message( $msg, ACTIVITY() );
}

# for backward compability
sub transport {
	my( $self, $msg, $level ) = @_;
	$level = DEBUG() unless defined ($level);
	_log_message( $msg, $level );
}



sub _log_message {
	my( $msg, $level ) = @_;
	return if $level > $loglevel;

	my $l; my $n; 
	my $fac = $facility;

	if ($level == ERROR())			{$l = LOG_ERR; $n = "ERR "; }
	elsif ($level == WARN())		{$l = LOG_WARNING; $n = "WARN"; }
	elsif ($level == INFO())		{$l = LOG_INFO; $n = "INFO"; }	
	elsif ($level == DEBUG())		{$l = LOG_DEBUG; $n = "DEBG"; }
	elsif ($level == INTERNAL())	{$l = LOG_DEBUG; $n = "INTL"; }
	elsif ($level == ACTIVITY())	{$l = LOG_INFO; $n = "ACT"; $fac = $actfac; }

	#my( $pack, $file, $line_no ) = @caller;

	if( $level == ACTIVITY() ) {
		if( is_act_syslog() ) { syslog( $fac | $l, $msg ); } 
		elsif( is_act_filelog() ) { _write_file( $msg, 1 ); }

	} else {
		if( is_syslog() ) { syslog( $fac | $l, $msg ); }
		elsif( is_filelog() ) { _write_file($msg); }
	}
}


sub _write_file {
	my( $msg, $isact) = @_;
	my $file = $logfile;
	$file = $actfile if $isact;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);  
	$year += 1900; $mon += 1;
	sysopen( SINK, $file, O_NONBLOCK|O_WRONLY|O_APPEND|O_CREAT ) 
		or die "Cannot sysopen $logfile: $!";
	binmode(SINK, ':utf8');
	print SINK "[$year-$mon-$mday $hour:$min:$sec] $service $msg\n";
	close( SINK );
}



1;
