use strict;
use warnings;
use utf8;

use Test::More tests => 50;
use Unicode::Normalize;
use DBI;

use OpenILS::Utils::Normalize qw( naco_normalize );

# This could be made better in at least one of two ways (or both);
# 1. put PL/Perl code that doesn't require a database into external
#    modules so that test frameworks can get at it more easily
# 2. Build a test harness that knows how to find an Evergreen
#    database to use for non-destructive testing.  Of course, there
#    can be a chicken-and-egg problem here; also, a complete test
#    suite would need to be able to do *destructive* testing, from
#    which we'd presumably want to protect production databases.

# Database connection parameters
my $db_driver = 'Pg';
my $db_host   = 'evergreen';
my $db_port   = '5432';
my $db_name   = 'evergreen';
my $db_user   = 'evergreen';
my $db_pw     = 'evergreen';
my $dsn       = "dbi:" . $db_driver . ":dbname=" . $db_name .';host=' . $db_host . ';port=' . $db_port;

binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

my @test_cases = (
    [ 'abc', 'abc', 'regular text' ],
    [ 'ABC', 'abc', 'regular text' ],
    [ 'åbçdéñœöîøæÇıÂÅÍÎÏÔÔÒÚÆŒè', 'abcdenoeoioaeciaaiiiooouaeoee', 'European diacritics' ],
    [ '“‘„«quotes»’”', 'quotes', 'special quotes' ],
    [ 'abc def', 'def', 'special non-filing characters designation' ],
    [ 'abcdef', 'abcdef', 'unpaired start of string' ],
    [ 'ß', 'ss', 'sharp S (eszett)' ],
    [ 'ﬂﬁﬀ', 'flfiff', 'ligatures' ],
    [ 'ƠơƯư²Ĳĳ', 'oouu2ijij', 'NFKD applied correctly' ],
    [ 'ÆØÞæðøþĐđıŁłŒœʻʼℓ', 'aeothaedothddilloeoel', 'part 3.6' ],
    [ 'Ð', 'd', 'uppercase eth (missing from 3.6?)' ],
    [ 'ıİ', 'ii', 'Turkish I' ],
    [ '[book\'s cover]', 'books cover', 'square brackets and apostrophe' ],
    [ '  grue   food ', 'grue food', 'trim spaces' ],
    # note addition of NFKD() to transform expected output
    [ '한국어 조선말', NFKD('한국어 조선말'), 'Korean text' ],
    [ '普通話 / 普通话', '普通話 普通话', 'Chinese text' ],
    [ 'العربية', 'العربية', 'Arabic text' ],
    [ 'ქართული ენა', 'ქართული ენა', 'Georgian text' ],
    [ 'русский язык', 'русскии язык', 'Russian text' ],
    [ "\r\npa\tper\f", 'paper', 'other whitespace' ],
    [ '#1: ∃ C++, @ home & abroad', '#1 c++ @ home & abroad', 'other punctuation' ],
    [ '٠١٢٣٤٥', '012345', 'other decimal digits' ],
    [ '²³¹', '231', 'superscript numbers' ],
    [ '♭©®♯', '♭ ♯', 'other symbols' ],
);

# test copy of naco_normalize in OpenILS::Utils::Normalize
foreach my $case (@test_cases) {
    is(naco_normalize($case->[0]), $case->[1], $case->[2] . ' (Normalize.pm)');
}
is(naco_normalize('Smith, Jane. Poet, painter, and author', 'a'),
    'smith, jane poet painter and author',
    'retain first comma (Normalize.pm)');

SKIP: {
    my $dbh = DBI->connect($dsn, $db_user, $db_pw, {AutoCommit => 1, pg_enable_utf8 => 1, PrintError => 0});
    skip "Failed to connect to database: $DBI::errstr", 25 if (!defined($dbh));

    # test stored procedure
    my $sth1 = $dbh->prepare_cached('SELECT public.naco_normalize(?)');
    my $sth2 = $dbh->prepare_cached('SELECT public.naco_normalize(?, ?)');
    sub naco_normalize_wrapper {
        my ($str, $sf) = @_;
        if (defined $sf) {
            $sth2->execute($str, $sf);
            return $sth2->fetchrow_array;
        } else {
            $sth1->execute($str);
            return $sth1->fetchrow_array;
        }
    }

    foreach my $case (@test_cases) {
        is(naco_normalize_wrapper($case->[0]), $case->[1], $case->[2] . ' (stored procedure)');
    }
    is(naco_normalize_wrapper('Smith, Jane. Poet, painter, and author', 'a'), 'smith, jane poet painter and author',
        'retain first comma (stored procedure)');
}
