package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::metabib;
use OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils::Cache;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;

my $log = 'OpenSRF::Utils::Logger';

$VERSION = 1;


sub search_full_rec {
	my $self = shift;
	my $client = shift;
	my $limiters = shift;
	my $term = shift;
	my $window = shift;
	$window = 100 unless (defined $window);

	my $cache_key = md5_hex(Dump($limiters).$term);

	my ($fts_col) = metabib::full_rec->columns('FTS');
	my $table = metabib::full_rec->table;

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value','index_vector');

	my $fts_where = $fts->sql_where_clause();
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

	$client->respond( [ @$recs[0 .. $window - 1] ] );

	OpenSRF::Utils::Cache->new->put_cache( $recs );

	return undef;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.metabib.full_rec.search_fts.value',
	method		=> 'search_full_rec',
	api_level	=> 1,
	stream		=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.metabib.full_rec.search_fts.index_vector',
	method		=> 'search_full_rec',
	api_level	=> 1,
	stream		=> 1,
);

sub search_class_fts {
	my $self = shift;
	my $client = shift;
	my $term = shift;
	my $ou = shift;
	my $ou_type = shift;
	my $window = shift;
	$window = 100 unless (defined $window);
	

	(my $class = $self->api_name) =~ s/.*metabib.(\w+).search_fts.*/$1/o;
	my $cache_key = md5_hex($class.$term.$ou.$ou_type);

	$log->debug("Cache key for $class search of '$term' at ($ou,$ou_type) will be $cache_key", DEBUG);

	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $class = $self->{cdbi};
	my $table = $class->table;

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value','index_vector');

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my $select = <<"	SQL";
		SELECT	m.metarecord, sum($rank)/count(m.source)
	  	  FROM	$table f,
			metabib.metarecord_source_map m,
			asset.call_number cn,
			$descendants d
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND cn.record = m.source
			AND cn.owning_lib = d.id
	  	  GROUP BY 1
	  	  ORDER BY 2 DESC;
	SQL

	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $recs = $class->db_Main->selectall_arrayref($select);
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	$client->respond( [ @$recs[0 .. $window - 1] ] );

	OpenSRF::Utils::Cache->new->put_cache( $recs );

	return undef;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.title.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::title_field_entry',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.author.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::author_field_entry',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.subject.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::subject_field_entry',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.keyword.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::keyword_field_entry',
);

sub search_class_fts_count {
	my $self = shift;
	my $client = shift;
	my $term = shift;
	my $ou = shift;
	my $ou_type = shift;

	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";
		

	my $class = $self->{cdbi};
	my $table = $class->table;

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value','index_vector');

	my $fts_where = $fts->sql_where_clause;

	# XXX test an "EXISTS version of descendant checking...
	my $select = <<"	SQL";
		SELECT	count(distinct  m.metarecord)
	  	  FROM	$table f,
			metabib.metarecord_source_map m,
			asset.call_number cn,
			$descendants d
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND cn.record = m.source
			AND cn.owning_lib = d.id;
	SQL

	$log->debug("Field Search Count SQL :: [$select]",DEBUG);

	my $recs = $class->db_Main->selectrow_arrayref($select)->[0];
	
	$log->debug("Count Search yielded $recs results.",DEBUG);

	return $recs;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.title.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::title_field_entry',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.author.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::author_field_entry',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.subject.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::subject_field_entry',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.keyword.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::keyword_field_entry',
);

1;
