package OpenILS::Utils::OfflineStore;
use base 'Class::DBI';
use DBI;
use OpenSRF::Utils::Config;

our $_file;
sub DBFile {
	my $class = shift;
	my $file = shift;
	$_file = $file if ($file);
	return $_file;
}

our $_dbh;
sub db_Main {
	my $self = shift;
	return $_dbh if ($_dbh);
	$_dbh = DBI->connect('dbi:SQLite:dbname='.$self->DBFile,'','');
	OpenILS::Utils::OfflineStore::Session->_create_table;
	OpenILS::Utils::OfflineStore::Script->_create_table;
	return $_dbh;
}



package OpenILS::Utils::OfflineStore::Session;
use base 'OpenILS::Utils::OfflineStore';

sub _create_table {
	my $self = shift;
	$self->db_Main->do( <<"	SQL" );

CREATE TABLE session (
	key			TEXT	UNIQUE PRIMARY KEY,
	org			INTEGER	NOT NULL,
	description	TEXT,
	creator		INTEGER NOT NULL,
	create_time	INTEGER NOT NULL,
	complete		INTEGER NOT NULL DEFAULT 0,
	in_process	INTEGER NOT NULL DEFAULT 0,
	start_time	INTEGER,
	end_time		INTEGER
);
CREATE INDEX IF NOT EXISTS session_pkey ON session (key);
CREATE INDEX IF NOT EXISTS session_org ON session (org);
CREATE INDEX IF NOT EXISTS session_creation ON session (create_time);

	SQL
}

__PACKAGE__->table('session');
__PACKAGE__->columns( Essential => qw/key org description 
	creator create_time complete in_process start_time end_time/);
__PACKAGE__->has_many(scripts => 'OpenILS::Utils::OfflineStore::Script');


package OpenILS::Utils::OfflineStore::Script;
use base 'OpenILS::Utils::OfflineStore';

sub _create_table {
	my $self = shift;
	$self->db_Main->do( <<"	SQL" );

CREATE TABLE script (
	id		INTEGER	UNIQUE PRIMARY KEY AUTOINCREMENT,
	session		TEXT	NOT NULL,
	requestor	INTEGER	NOT NULL,
	timestamp	INTEGER	NOT NULL,
	workstation	TEXT	NOT NULL,
	logfile		TEXT	NOT NULL,
	time_delta	INTEGER	NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS script_pkey ON script (id);
CREATE INDEX IF NOT EXISTS script_ws ON script (workstation);
CREATE INDEX IF NOT EXISTS script_session ON script (session);

	SQL
}

__PACKAGE__->table('script');
__PACKAGE__->columns( Essential => qw/id session requestor timestamp workstation logfile time_delta/);
__PACKAGE__->has_a(session => 'OpenILS::Utils::OfflineStore::Session');





