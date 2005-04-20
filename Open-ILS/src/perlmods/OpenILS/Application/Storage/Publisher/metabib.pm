package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage::Publisher/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils::Cache;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;

my $log = 'OpenSRF::Utils::Logger';

$VERSION = 1;

sub metarecord_copy_count {
	my $self = shift;
	my $client = shift;

	my %args = @_;

	my $sm_table = metabib::metarecord_source_map->table;
	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;
	my $out_table = actor::org_unit_type->table;
	my $descendants = "actor.org_unit_descendants(u.id)";
	my $ancestors = "actor.org_unit_ancestors(?)";

	my $sql = <<"	SQL";
		SELECT	t.depth,
			u.id AS org_unit,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE r.metarecord = ?)
			) AS count,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE r.metarecord = ?
				  	AND cp.status = 0)
			) AS available

		  FROM  $ancestors u
			JOIN $out_table t ON (u.ou_type = t.id)
		  GROUP BY 1,2
	SQL

	my $sth = metabib::metarecord_source_map->db_Main->prepare_cached($sql);
	$sth->execute(''.$args{metarecord}, ''.$args{metarecord}, ''.$args{org_unit});
	while ( my $row = $sth->fetchrow_hashref ) {
		$client->respond( $row );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.metarecord.copy_count',
	method		=> 'metarecord_copy_count',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

sub search_full_rec {
	my $self = shift;
	my $client = shift;

	my %args = @_;
	
	my $term = $args{term};
	my $limiters = $args{restrict};

	my ($index_col) = metabib::full_rec->columns('FTS');
	$index_col ||= 'value';
	my $search_table = metabib::full_rec->table;

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value',"$index_col");

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

	my $select = "SELECT record, sum($rank) FROM $search_table WHERE $where GROUP BY 1 ORDER BY 2 DESC;";

	$log->debug("Search SQL :: [$select]",DEBUG);

	my $recs = metabib::full_rec->db_Main->selectall_arrayref($select, {}, @binds);
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	$client->respond($_) for (@$recs);
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.metabib.full_rec.search_fts.value',
	method		=> 'search_full_rec',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.metabib.full_rec.search_fts.index_vector',
	method		=> 'search_full_rec',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);


# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub search_class_fts {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $term = $args{term};
	my $ou = $args{org_unit};
	my $ou_type = $args{depth};


	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value', "$index_col");

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my $select = <<"	SQL";
		SELECT	m.metarecord, sum($rank)/count(m.source)
	  	  FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$asset_call_number_table cn,
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

	$client->respond($_) for (@$recs);
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.title.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::title_field_entry',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.author.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::author_field_entry',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.subject.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::subject_field_entry',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.keyword.search_fts.metarecord',
	method		=> 'search_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::keyword_field_entry',
	cachable	=> 1,
);

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub search_class_fts_count {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $term = $args{term};
	my $ou = $args{org_unit};
	my $ou_type = $args{depth};
	my $limit = $args{limit} || 100;
	my $offset = $args{offset} || 0;

	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";
		

	(my $search_class = $self->api_name) =~ s/.*metabib.(\w+).search_fts.*/$1/o;
	my $cache_key = md5_hex($search_class.$term.$ou.$ou_type.'_COUNT_');

	my $cached_recs = OpenSRF::Utils::Cache->new->get_cache( $cache_key );
	return $cached_recs if (defined $cached_recs);

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value',"$index_col");

	my $fts_where = $fts->sql_where_clause;

	# XXX test an "EXISTS version of descendant checking...
	my $select = <<"	SQL";
		SELECT	count(distinct  m.metarecord)
	  	  FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$asset_call_number_table cn,
			$descendants d
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND cn.record = m.source
			AND cn.owning_lib = d.id;
	SQL

	$log->debug("Field Search Count SQL :: [$select]",DEBUG);

	my $recs = $class->db_Main->selectrow_arrayref($select)->[0];
	
	$log->debug("Count Search yielded $recs results.",DEBUG);

	OpenSRF::Utils::Cache->new->put_cache( $cache_key => $recs );

	return $recs;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.title.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::title_field_entry',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.author.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::author_field_entry',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.subject.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::subject_field_entry',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.keyword.search_fts.metarecord_count',
	method		=> 'search_class_fts_count',
	api_level	=> 1,
	stream		=> 1,
	cdbi		=> 'metabib::keyword_field_entry',
	cachable	=> 1,
);

1;
