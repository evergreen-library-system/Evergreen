package OpenILS::Utils::ZClient;
use UNIVERSAL::require;

our $conn_class = 'ZOOM::Connection';
our $imp_class = 'ZOOM';

# Detect the installed z client, prefering ZOOM.
if (!$imp_class->use()) {

	$imp_class = 'Net::Z3950';  # Try Net::Z3950
	if ($imp_class->use()) {

		# Load the modules we're going to modify
		'Net::Z3950::Connection'->use();
		'Net::Z3950::ResultSet'->use();
		'Net::Z3950::Record'->use();

		# Tell 'new' how to build the connection
		$conn_class = 'Net::Z3950::Connection';
		
		# Now we're going to give Net::Z3950 a ZOOM-ish interface

		# Move 'record' out of the way ...
		*{'Net::Z3950::ResultSet::_real_record'}  = *{'Net::Z3950::ResultSet::record'};
		# ... and install a new version using the 0-based ZOOM semantics
		*{'Net::Z3950::ResultSet::record'}  = sub { return shift()->_real_record(shift() - 1); };

		# Alias 'search' with the ZOOM 'search_pqf' method
		*{'Net::Z3950::Connection::search_pqf'}  = *{'Net::Z3950::Connection::search'};

		# And finally, alias 'rawdata' with the ZOOM 'raw' method
		*{'Net::Z3950::Record::raw'}  = sub { return shift()->rawdata(@_); }

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

	return $conn_class->new(@_);
}


1;

