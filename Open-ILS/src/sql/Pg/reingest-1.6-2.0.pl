#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use DBI;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;

my ($config, $chunk_size, $output) = ('/openils/conf/opensrf_core.xml', 0, 'reingest-1.6-2.0.sql');

GetOptions(
        "config:s"      => \$config,
        "chunk_size:i"  => \$chunk_size,
        "output:s"      => \$output,
);

print qq{$0: generate SQL script to reingest bibs during an upgrade to Evergreen 2.0

By default, the script writes to the file reingest-1.6-2.0.sql.  To modify
this script's behavior, you can supply the following options:

--config /path/to/opensrf_core.xml  used to get connection information to
                                    the Evergreen database
--chunk_size n                      number of bibs to reingest in a chunk;
                                    specify if you don't want all of the 
                                    bibs in the database to be reindexes
                                    in a single transaction
--output /path/to/output_file.sql   path of output SQL file

};

open OUT, ">$output" or die "$0: cannot open output file $output: $!\n";
print "Writing output to file $output\n";
my $num_bibs;
$num_bibs = fetch_num_bibs_from_database($config) if $chunk_size;

header();
body($num_bibs, $chunk_size);
footer();

print qq{
SQL script complete.  To perform the reingest, please run the script using
the psql program, e.g.,

psql {connection parameters}  < $output

If you are running a large Evergreen installation, it is recommend that you
examine the script first; note that a reingest of a large Evergreen database
can take several hours.
};

sub fetch_num_bibs_from_database {
    my $config = shift;
    OpenSRF::System->bootstrap_client( config_file => $config );
    my $sc = OpenSRF::Utils::SettingsClient->new;
    my $db_driver = $sc->config_value( reporter => setup => database => 'driver' );
    my $db_host = $sc->config_value( reporter => setup => database => 'host' );
    my $db_port = $sc->config_value( reporter => setup => database => 'port' );
    my $db_name = $sc->config_value( reporter => setup => database => 'db' );
    if (!$db_name) {
        $db_name = $sc->config_value( reporter => setup => database => 'name' );
    }
    my $db_user = $sc->config_value( reporter => setup => database => 'user' );
    my $db_pw = $sc->config_value( reporter => setup => database => 'pw' );
    die "Unable to retrieve database connection information from the settings server" 
        unless ($db_driver && $db_host && $db_port && $db_name && $db_user);

    my $dsn = "dbi:" . $db_driver . ":dbname=" . $db_name .';host=' . $db_host . ';port=' . $db_port;
    my $dbh = DBI->connect($dsn, $db_user, $db_pw, {AutoCommit => 1, pg_enable_utf8 => 1, RaiseError => 1});
    my $count = $dbh->selectrow_array('SELECT COUNT(*) FROM biblio.record_entry WHERE id > -1 AND NOT deleted');
    return $count;
}

sub header {
    print OUT q {
\qecho First, make sure that the rows needed for title sorting are
\qecho available.

BEGIN; 
DELETE FROM metabib.real_full_rec WHERE tag = 'tnf'; 
INSERT INTO metabib.real_full_rec (record, tag, subfield, value) 
   SELECT  record, 
           'tnf', 
           'a', 
           SUBSTRING(value, COALESCE(NULLIF(REGEXP_REPLACE(ind2,'[^0-9]','','g'),''),'0')::int + 1) 
     FROM  metabib.real_full_rec 
     WHERE tag = '245' 
           AND subfield = 'a'; 
COMMIT;

\qecho Do a partial reingest to fully populate metabib.facet_entry
\qecho and update the keyword indexes to reflect changes in the default
\qecho NACO normalization.  This can be time consuming on large databases.

\qecho public.upgrade_2_0_partial_bib_reingest is a thin wrapper around
\qecho metabib.reingest_metabib_field_entries, which does the actual
\qecho work; its main purpose is to suggest a means of doing the reingest
\qecho piecemeal if there isn't sufficient time in the upgrade window
\qecho to do it in one fell swoop.
CREATE OR REPLACE FUNCTION public.upgrade_2_0_partial_bib_reingest( l_offset BIGINT, l_limit BIGINT ) RETURNS VOID AS $func$
BEGIN
   PERFORM metabib.reingest_metabib_field_entries(id)
       FROM biblio.record_entry
       WHERE id IN (
       SELECT id  
       FROM biblio.record_entry
       WHERE id > -1
       AND NOT deleted
       ORDER BY id
       OFFSET l_offset
       LIMIT l_limit
   );
END;
$func$ LANGUAGE PLPGSQL;
};
}

sub body {
    my ($num_bibs, $chunk_size) = @_;
    if ($num_bibs && $chunk_size) {
        for (my $i = 0; $i <= $num_bibs / $chunk_size; $i++) {
            print OUT qq{SELECT public.upgrade_2_0_partial_bib_reingest($i * $chunk_size, $chunk_size);\n};
        }
    } else {
        print OUT q{
SELECT public.upgrade_2_0_partial_bib_reingest(0, (SELECT COUNT(*) FROM biblio.record_entry WHERE id > -1 AND NOT deleted));
        };
    }
}

sub footer {
    print OUT q{
-- clean up after ourselves
DROP FUNCTION public.upgrade_2_0_partial_bib_reingest(BIGINT, BIGINT);

VACUUM ANALYZE metabib.keyword_field_entry;
VACUUM ANALYZE metabib.author_field_entry;
VACUUM ANALYZE metabib.subject_field_entry;
VACUUM ANALYZE metabib.title_field_entry;
VACUUM ANALYZE metabib.series_field_entry;
VACUUM ANALYZE metabib.identifier_field_entry;
VACUUM ANALYZE metabib.facet_entry;
};
}
 
