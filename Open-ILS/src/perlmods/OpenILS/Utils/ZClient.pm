package OpenILS::Utils::ZClient;
use UNIVERSAL::require;

use overload 'bool' => sub { return $_[0]->{connection} ? 1 : 0 };

our $conn_class = 'ZOOM::Connection';
our $imp_class = 'ZOOM';
our $AUTOLOAD;

# Detect the installed z client, prefering ZOOM.
if (!$imp_class->use()) {

	$imp_class = 'Net::Z3950';  # Try Net::Z3950
	if ($imp_class->use()) {

		# Tell 'new' how to build the connection
		$conn_class = 'Net::Z3950::Connection';
		
	} else {
		die "Cannot load a z39.50 client implementation!  Please install either ZOOM or Net::Z3950.\n";
	}
}

# 'new' is called thusly:
#  my $conn = OpenILS::Utils::ZClient->new( $host, $port, databaseName => $db, user => $username )

sub new {
	my $class = shift();
	my @args = @_;

	if ($class ne __PACKAGE__) { # NOT called OO-ishly
		# put the first param back if called like OpenILS::Utils::ZClient::new()
		unshift @args, $class;
	}

	return bless { connection => $conn_class->new(@_) } => __PACKAGE__;
}

sub search {
	my $self = shift;
	my $r =  $imp_class eq 'Net::Z3950' ?
		$self->{connection}->search( @_ ) :
		$self->{connection}->search_pqf( @_ );

	return OpenILS::Utils::ZClient::ResultSet->new( $r );
}

sub event {
	my $list = shift;
	if ($imp_class eq 'Net::Z3950') {
		if (defined $$list[0]{_async_index}) {	
			return 0 if ($$list[0]{_async_index} == @$list);
			return ++$$list[0]{_async_index};
		} else {
			return $$list[0]{_async_index} = 1;
		}
	}

	return ZOOM::event([map { ($_->{result}) } @$list]);
}

*{__PACKAGE__ . '::search_pqf'} = \&search; 

sub AUTOLOAD {
	my $self = shift;

	my $method = $AUTOLOAD;
	$method =~ s/.*://;   # strip fully-qualified portion

	return $self->{connection}->$method( @_ );
}

#-------------------------------------------------------------------------------
package OpenILS::Utils::ZClient::ResultSet;

our $AUTOLOAD;

sub new {
	my $class = shift;
	my @args = @_;

	if ($class ne __PACKAGE__) { # NOT called OO-ishly
		# put the first param back if called like OpenILS::Utils::ZClient::ResultSet::new()
		unshift @args, $class;
	}


	return bless { result => $args[0] } => __PACKAGE__;
}

sub record {
	my $self = shift;
	my $offset = shift;
	my $r = $imp_class eq 'Net::Z3950' ?
		$self->{result}->record( ++$offset ) :
		$self->{result}->record( $offset );

	return  OpenILS::Utils::ZClient::Record->new( $r );
}

sub last_event {
	my $self = shift;
	return OpenILS::Utils::ZClient::Event::EVENT_END if ($imp_class eq 'Net::Z3950');
	$self->{result}->last_event();
}

sub AUTOLOAD {
	my $self = shift;

	my $method = $AUTOLOAD;
	$method =~ s/.*://;   # strip fully-qualified portion

	return $self->{result}->$method( @_ );
}

#-------------------------------------------------------------------------------
package OpenILS::Utils::ZClient::Record;

our $AUTOLOAD;

sub new {
	my $class = shift;
	my @args = @_;

	if ($class ne __PACKAGE__) { # NOT called OO-ishly
		# put the first param back if called like OpenILS::Utils::ZClient::ResultSet::new()
		unshift @args, $class;
	}


	return bless { record => shift() } => __PACKAGE__;
}

sub rawdata {
	my $self = shift;
	return $OpenILS::Utils::ZClient::imp_class eq 'Net::Z3950' ?
		$self->{record}->rawdata( @_ ) :
		$self->{record}->raw( @_ );
}

*{__PACKAGE__ . '::raw'} = \&rawdata; 

sub AUTOLOAD {
	my $self = shift;

	my $method = $AUTOLOAD;
	$method =~ s/.*://;   # strip fully-qualified portion

	return $self->{record}->$method( @_ );
}

#-------------------------------------------------------------------------------
package OpenILS::Utils::ZClient::Event;

sub NONE { 0 }
sub CONNECT { 1 }
sub SEND_DATA { 2 }
sub RECV_DATA { 3 }
sub TIMEOUT { 4 }
sub UNKNOWN { 5 }
sub SEND_APDU { 6 }
sub RECV_APDU { 7 }
sub RECV_RECORD { 8 }
sub RECV_SEARCH { 9 }
sub END { 10 }

1;

