package OpenSRF::Utils::LogServer;
use strict; use warnings;
use base qw(OpenSRF);
use IO::Socket::INET;
use FileHandle;
use OpenSRF::Utils::Config;
use Fcntl;
use Time::HiRes qw(gettimeofday);
use OpenSRF::Utils::Logger;

=head2 Name

OpenSRF::Utils::LogServer

=cut

=head2 Synopsis

Networ Logger

=cut

=head2 Description


=cut



our $config;
our $port;
our $bufsize = 4096;
our $proto;
our @file_info;


sub DESTROY {
	for my $file (@file_info) {
		if( $file->handle ) {
			close( $file->handle );
		}
	}
}


sub serve {

	$config = OpenSRF::Utils::Config->current;

	unless ($config) { throw OpenSRF::EX::Config ("No suitable config found"); }

	$port = $config->system->log_port;
	$proto = $config->system->log_proto;


	my $server = IO::Socket::INET->new(
		LocalPort	=> $port,
		Proto			=> $proto )
	or die "Error creating server socket : $@\n"; 



	while ( 1 ) {
		my $client = <$server>;
		process( $client );
	}

	close( $server );
}

sub process {
	my $client = shift;
	my @params = split(/\|/,$client);
	my $log = shift @params;

	if( (!$log) || (!@params) ) {
		warn "Invalid logging params: $log\n";
		return;
	}

	# Put |'s back in since they are stripped 
	# from the message by 'split'
	my $message;
	if( @params > 1 ) {
		foreach my $param (@params) {
			if( $param ne $params[0] ) {
				$message .= "|";
			}
			$message .= $param;
		}
	}
	else{ $message = "@params"; }

	my @lines = split( "\n", $message );
	my $time = format_time();

	my $fh;

	my ($f_obj) = grep { $_->name eq $log } @file_info;

	unless( $f_obj and ($fh=$f_obj->handle) ) {
		my $file = $config->logs->$log;

		sysopen( $fh, $file, O_WRONLY|O_APPEND|O_CREAT ) 
			or warn "Cannot sysopen $log: $!";
		$fh->autoflush(1);

		my $obj = new OpenSRF::Utils::NetLogFile( $log, $file, $fh );
		push @file_info, $obj;
	}

	foreach my $line (@lines) {
		print $fh "$time $line\n" || die "$!";
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


package OpenSRF::Utils::NetLogFile;

sub new{ return bless( [ $_[1], $_[2], $_[3] ], $_[0] ); }

sub name { return $_[0]->[0]; }
sub file { return $_[0]->[1]; }
sub handle { return $_[0]->[2]; }


1;
