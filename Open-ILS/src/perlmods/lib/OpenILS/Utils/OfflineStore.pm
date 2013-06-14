package OpenILS::Utils::OfflineStore;
use strict; use warnings;

use UNIVERSAL::require;
if ('Class::DBI::Frozen::301'->use) {
    use parent 'Class::DBI::Frozen::301';
} elsif ('Class::DBI'->use) {
    use parent 'Class::DBI';
} else {
    die $@;
}

use DBI;
use OpenSRF::Utils::Config;

our ($_dsn,$_u,$_p);
sub DBFile {
    my $class = shift;
    my $dsn = shift;
    my $u = shift;
    my $p = shift;
    if ($dsn) {
        $_dsn = $dsn;
        $_u = $u;
        $_p = $p;
    }
    return $_dsn;
}

our $_dbh;
sub db_Main {
    my $self = shift;
    return $_dbh if ($_dbh);

    $_dbh = DBI->connect($_dsn,$_u,$_p,
        {
            RootClass => 'DBIx::ContextualFetch' 
        }
    );

    return $_dbh;
}


sub disconnect {
    $_dbh->disconnect;
    $_dbh = undef;
}


package OpenILS::Utils::OfflineStore::Session;
use parent 'OpenILS::Utils::OfflineStore';

sub _create_table {
    my $self = shift;
    $self->db_Main->do( <<"    SQL" );

CREATE TABLE session (
    key             TEXT    UNIQUE PRIMARY KEY,
    org             INTEGER NOT NULL,
    description     TEXT,
    creator         INTEGER NOT NULL,
    create_time     INTEGER NOT NULL,
    in_process      INTEGER NOT NULL DEFAULT 0,
    start_time      INTEGER,
    end_time            INTEGER,
    num_complete    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS session_pkey ON session (key);
CREATE INDEX IF NOT EXISTS session_org ON session (org);
CREATE INDEX IF NOT EXISTS session_creation ON session (create_time);

    SQL
}

__PACKAGE__->table('offline.session');
__PACKAGE__->columns( Essential => qw/key org description 
        creator create_time in_process start_time end_time num_complete/);
__PACKAGE__->has_many(scripts => 'OpenILS::Utils::OfflineStore::Script');


package OpenILS::Utils::OfflineStore::Script;
use parent 'OpenILS::Utils::OfflineStore';

sub _create_table {
    my $self = shift;
    $self->db_Main->do( <<"    SQL" );

CREATE TABLE script (
    id      INTEGER UNIQUE PRIMARY KEY AUTOINCREMENT,
    session     TEXT    NOT NULL,
    requestor   INTEGER NOT NULL,
    create_time INTEGER NOT NULL,
    workstation TEXT    NOT NULL,
    logfile     TEXT    NOT NULL,
    time_delta  INTEGER NOT NULL DEFAULT 0,
    count           INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS script_pkey ON script (id);
CREATE INDEX IF NOT EXISTS script_ws ON script (workstation);
CREATE INDEX IF NOT EXISTS script_session ON script (session);

    SQL
}

__PACKAGE__->table('offline.script');
__PACKAGE__->columns( Essential => qw/id session requestor create_time workstation logfile time_delta count/);
__PACKAGE__->has_a(session => 'OpenILS::Utils::OfflineStore::Session');
__PACKAGE__->sequence(qw/offline.script_id_seq/);





