package OpenSRF::Utils::Logger;
use strict;
use vars qw($AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use base qw/OpenSRF Exporter/;
use FileHandle;
use Time::HiRes qw(gettimeofday);
use OpenSRF::Utils::Config;
use Fcntl;

@EXPORT_OK = qw/ NONE ERROR WARN INFO DEBUG INTERNAL /;

%EXPORT_TAGS = ( level => [ qw/ NONE ERROR WARN INFO DEBUG INTERNAL / ] );

# XXX Update documentation

=head1 Description

OpenSRF::Utils::Logger

General purpose logging package.  The logger searches $config->logs->$log_name for the 
actual file to log to.  Any file in the config may be logged to.  If the user attempts to 
log to a log file that does not exist within the config, then the messages will to 
to STDERR.  

There are also a set of predefined log levels.  Currently they are
NONE, ERROR, WARN, INFO, DEBUG, INTERNAL, and ALL.  You can select one of these log levels
when you send messages to the logger.  The message will be logged if it is of equal or greater
'importance' than the global log level, found at $config->system->debug.  If you don't specify
a log level, a defaul will be provided.  Current defaults are:

error			-> ERROR

debug			-> DEBUG

transport	-> INTERNAL

message		-> INFO

method		-> INFO

All others are logged to INFO by default.

You write to a log by calling the log's method.  

use OpenSRF::Utils::Logger qw(:level);

my $logger = "OpenSRF::Utils::Logger";

$logger->debug( "degug message" );
$logger->transport( "debug message", DEBUG );
$logger->blahalb( "I'll likely end up at STDERR with a log level of INFO" );

will only write the time, line number, and file that the method was called from.

Note also that all messages with a log level of ERROR are written to the "error" log
in addition to the intended log file.

=cut

# Just set this first and not during every call to the logger
# XXX this should be added to the sig{hup} handler once it exists.


##############
#   1. check config, if file exists write to that file locally
#	2. If not in config and set to remote, send to socket.  if not remote log to stderr

my $config; 
my $file_hash;
my $trace_active = 0;

my $port;
my $proto;
my $peer;
my $socket;
my $remote_logging = 0;

my $LEVEL = "OpenSRF::Utils::LogLevel";
my $FILE	= "OpenSRF::Utils::LogFile";

# --- Log levels - values and names

my $none			= $LEVEL->new( 1,		"NONE" ); 
my $error		= $LEVEL->new( 10,	"ERRR" ); 
my $warn			= $LEVEL->new( 20,	"WARN" ); 
my $info			= $LEVEL->new( 30,	"INFO" );
my $debug		= $LEVEL->new( 40,	"DEBG" );
my $internal	= $LEVEL->new( 50,	"INTL" );
my $all			= $LEVEL->new( 100,	"ALL " );


sub NONE			{ return $none;	} 
sub ERROR		{ return $error;	} 
sub WARN			{ return $warn;	} 
sub INFO			{ return $info;	} 
sub DEBUG		{ return $debug;	} 
sub INTERNAL	{ return $internal; }
sub ALL			{ return $all;		}

# Known log files and their default log levels
my $known_logs = [
	$FILE->new( "error",		&ERROR ),
	$FILE->new( "debug",		&DEBUG ),
	$FILE->new( "transport",&INTERNAL ),
	$FILE->new( "message",	&INFO ),
	$FILE->new( "method",	&INFO ),
	];




# ---------------------------------------------------------

{
	my $global_llevel;
	sub global_llevel { return $global_llevel; }

	sub set_config {

		$config = OpenSRF::Utils::Config->current;

		if( defined($config) ) { 

			$global_llevel =  $config->system->debug; 
			$port = $config->system->log_port;
			$proto = $config->system->log_proto;
			$peer = $config->system->log_server;
			$remote_logging = $config->system->remote_log;

			{
				no strict "refs";
				$global_llevel = &{$global_llevel};
			}
			#$trace_active = $config->system->trace;
			build_file_hash();
		}

		else { 
			$global_llevel = DEBUG; 
			warn "*** Logger found no suitable config.  Using STDERR ***\n";
		}
	}
}

sub build_file_hash { 
	$file_hash = {};
	# XXX This breaks Config encapsulation and should be cleaned.
	foreach my $log ( grep { !($_ =~ /__id/) } (keys %{$config->logs}) ) {
		$file_hash->{$log} = $config->logs->$log;
	}
}

# ---------------------------------------------------------

sub AUTOLOAD {


	my( $self, $string, $llevel ) = @_;
	my $log		= $AUTOLOAD;
	$log			=~ s/.*://;   # strip fully-qualified portion

	unless( defined($config) or global_llevel() ) {
		set_config();
	}

	# Build the sub here so we can use the enclosed $log variable.
	# This is some weird Perl s*** that only satan could dream up.
	# We mangle the symbol table so that future calls to $logger->blah
	# will no longer require the autoload.  
	# The $log variable (above) will contain the name of the log 
	# log file the user is attempting to log to.  This is true, however,  
	# even though the above code is presumably run only the first time
	# the call to $logger->blah is made.  

	no strict "refs";

	*{$log} = sub { 

		if( global_llevel()->level == NONE->level ) { return; }

		my( $class, $string, $llevel ) = @_;

		# see if we can return
		if( $llevel ) { 
			# if level is passed in as a string, cast it to a level object
			ref( $llevel ) || do{ $llevel = &{$llevel} };
			return if ($llevel->level > global_llevel()->level); 
		}

		else { # see if there is a default llevel, set to INFO if not.
			my $log_obj;
			foreach my $l ( @$known_logs ) {
				if( $l->name eq $log ) { $log_obj = $l and last; }
			}
			if( $log_obj ) { $llevel = $log_obj->def_level; }
			else { $llevel = INFO; }
		}


		# again, see if we can get out of this 
		return if ($llevel->level > global_llevel()->level); 
	
		my @caller = caller();
		push( @caller, (caller(1))[3] );

		# In the absense of a config, we write to STDERR

		if( ! defined($config)  ) { 
			_write_stderr( $string, $llevel->name, @caller); 
			return;
		}

		if( $remote_logging ) {
			_write_net( $log, $string, $llevel->name, @caller );
		
		} elsif ( my $file = $file_hash->{$log} ) {
			_write_local( $file, $string, $llevel->name, @caller );

		} else {
			_write_stderr( $string, $llevel->name, @caller); 
		}

	
		if( $llevel->name eq ERROR->name ) { # send all error to stderr
			_write_stderr( $string, $llevel->name, @caller); 
		}

		if( $llevel->name eq ERROR->name and $log ne "error" ) {
			if( my $e_file = $file_hash->{"error"}  ) {
				if( ! $remote_logging ) {
					_write_local( $e_file, $string, $llevel->name, @caller );
				}
			}
		}
	
	};
	
	$self->$log( $string, $llevel );
}


# write_net expects a log_type_name and not a log_file_name for the first parameter
my $net_buffer = "";
my $counter = 0;
sub _write_net {


	my( $log, $string, $llevel, @caller ) = @_;
	my( $pack, $file, $line_no ) = @caller;
	my @lines = split( "\n", $string );

	my $message = "$log|"."-" x 33 . 
		"\n$log|[$0 $llevel] $line_no $pack".
		"\n$log|[$0 $llevel] $file";

	foreach my $line (@lines) {
		$message .= "\n$log|[$0 $llevel] $line";
	}

	$net_buffer .= "$message\n";

	# every 4th load is sent on the socket
	if( $counter++ % 4 ) { return; }

	unless( $socket ) {
		$socket = IO::Socket::INET->new(
				PeerAddr	=> $peer,
				PeerPort	=> $port,
				Proto		=> $proto )
			or die "Unable to open socket to log server";  
	}

	$socket->send( $net_buffer );
	$net_buffer = "";

}

sub _write_local {

	my( $log, $string, $llevel, @caller ) = @_;
	my( $pack, $file, $line_no ) = @caller;
	my @lines = split( "\n", $string );
	my $time = format_time();
	sysopen( SINK, $log, O_NONBLOCK|O_WRONLY|O_APPEND|O_CREAT ) 
		or die "Cannot sysopen $log: $!";
	binmode(SINK, ':utf8');
	print SINK "-" x 23 . "\n";
	print SINK "$time [$0 $llevel] $line_no $pack \n";
	print SINK "$time [$0 $llevel] $file\n";
	foreach my $line (@lines) {
		print SINK "$time [$0 $llevel] $line\n";
	}
	close( SINK );

}

sub _write_stderr {
	my( $string, $llevel, @caller ) = @_;
	my( $pack, $file, $line_no ) = @caller;
	my @lines = split( "\n", $string );
	my $time = format_time();
	print STDERR "-" x 23 . "\n";
	print STDERR "$time [$0 $llevel] $line_no $pack\n";
	print STDERR "$time [$0 $llevel] $file\n";
	foreach my $line (@lines) {
		print STDERR "$time [$0 $llevel] $line\n";
	}
}

sub format_time {
	my ($s, $ms) = gettimeofday();
	my @time = localtime( $s );
	$ms = substr( $ms, 0, 3 );
	my $year = $time[5] + 1900;
	my $mon = $time[4] + 1;
	my $day = $time[3];
	my $hour = $time[2];
	my $min = $time[1];
	my $sec = $time[0];
	$mon = "0" . "$mon" if ( length($mon) == 1 );
	$day = "0" . "$day" if ( length($day) == 1 );
	$hour = "0" . "$hour" if ( length($hour) == 1 );
	$min = "0" . "$min" if (length($min) == 1 );
	$sec = "0" . "$sec" if (length($sec) == 1 );

	my $proc = $$;
	while( length( $proc ) < 5 ) { $proc = "0" . "$proc"; }
	return "[$year-$mon-$day $hour:$min:$sec.$ms $proc]";
}


# ----------------------------------------------
# --- Models a log level
package OpenSRF::Utils::LogLevel;

sub new { return bless( [ $_[1], $_[2] ], $_[0] ); }

sub level { return $_[0]->[0]; }
sub name	{ return $_[0]->[1]; }

# ----------------------------------------------

package OpenSRF::Utils::LogFile;
use OpenSRF::Utils::Config;

sub new{ return bless( [ $_[1], $_[2] ], $_[0] ); }

sub name { return $_[0]->[0]; }
sub def_level { return $_[0]->[1]; }


# ----------------------------------------------

1;
