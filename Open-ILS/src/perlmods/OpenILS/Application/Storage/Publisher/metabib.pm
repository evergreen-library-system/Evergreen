package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::metabib;
use OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger;

my $log = 'OpenSRF::Utils::Logger';

$VERSION = 1;


sub search_full_rec {
	my $self = shift;
	my $client = shift;
	my $limiters = shift;
	my $term = shift;

	my ($fts_col) = metabib::full_rec->columns('FTS');
	my $table = metabib::full_rec->table;

	my $fts = OpenILS::Application::Storage::FTS->compile($term);

	my $fts_where = $fts->sql_where_clause($fts_col);
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my @binds;
	my @wheres;
	for my $limit (@$limiters) {
		push @wheres, "( tag = ? AND subfield LIKE ? AND $fts_where )";
		push @binds, $$limit{tag}, $$limit{subfield};
 		$log->debug("Limiting query using { tag => $$limit{tag}, subfield => $$limit{subfield} }", DEBUG);
	}
	my $where = join(' OR ', @wheres);

	my $select = "SELECT record, sum($rank) FROM $table WHERE $where GROUP BY 1 ORDER BY 2 DESC;";

	$log->debug("Search SQL :: [$select]",DEBUG);

	my $recs = metabib::full_rec->db_Main->selectall_arrayref($select, {}, @binds);
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);
	return $recs;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.full_rec.search.fts',
	method		=> 'search_full_rec',
	api_level	=> 1,
	stream		=> 1,
);


1;
