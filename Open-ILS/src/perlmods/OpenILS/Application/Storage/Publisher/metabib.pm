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

# need to order record IDs by:
#  1) format - text, movie, sound, software, images, maps, mixed, music, 3d
#  2) proximity --- XXX Can't do it cheap...
#  3) count
sub ordered_records_from_metarecord {
	my $self = shift;
	my $client = shift;
	my $mr = shift;

	my $copies_visible = 'AND cp.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my $sm_table = metabib::metarecord_source_map->table;
	my $rd_table = metabib::record_descriptor->table;
	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;
	my $out_table = actor::org_unit_type->table;

	my $sql = <<"	SQL";
		SELECT	cn.record,
			rd.item_type,
                        sum((SELECT	count(cp.id)
	                       FROM	$cp_table cp
	                       WHERE	cn.id = cp.call_number
	                                $copies_visible
			  )) AS count
		  FROM	$cn_table cn,
			$sm_table sm,
			$rd_table rd
		  WHERE	cn.record = sm.source
		  	AND cn.record = rd.record
			AND sm.metarecord = ?
		  GROUP BY cn.record, rd.item_type
		  ORDER BY
			CASE
				WHEN rd.item_type IS NULL -- default
					THEN 0
				WHEN rd.item_type = '' -- default
					THEN 0
				WHEN rd.item_type IN ('a','t') -- books
					THEN 1
				WHEN rd.item_type = 'g' -- movies
					THEN 2
				WHEN rd.item_type IN ('i','j') -- sound recordings
					THEN 3
				WHEN rd.item_type = 'm' -- software
					THEN 4
				WHEN rd.item_type = 'k' -- images
					THEN 5
				WHEN rd.item_type IN ('e','f') -- maps
					THEN 6
				WHEN rd.item_type IN ('o','p') -- mixed
					THEN 7
				WHEN rd.item_type IN ('c','d') -- music
					THEN 8
				WHEN rd.item_type = 'r' -- 3d
					THEN 9
			END,
			count DESC
	SQL

	my $sth = metabib::metarecord_source_map->db_Main->prepare_cached($sql);
	$sth->execute("$mr");
	while ( my $row = $sth->fetchrow_arrayref ) {
		$client->respond( $$row[0] );
	}
	return undef;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.ordered.metabib.metarecord.records',
	method		=> 'ordered_records_from_metarecord',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.ordered.metabib.metarecord.records.staff',
	method		=> 'ordered_records_from_metarecord',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);


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

	my $copies_visible = 'AND cp.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my $sql = <<"	SQL";
		SELECT	t.depth,
			u.id AS org_unit,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE r.metarecord = ?
				  	$copies_visible
				)
			) AS count,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE r.metarecord = ?
				  	AND cp.status = 0
					$copies_visible
				)
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
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.metarecord.copy_count.staff',
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
	my $limit = $args{limit};
	my $offset = $args{offset};

	my $limit_clause = '';
	my $offset_clause = '';

	$limit_clause = "LIMIT $limit" if (defined $limit and int($limit) > 0);
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);


	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_full_rec = metabib::full_rec->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'f.value', "f.$index_col");

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE';

	my $visible_count = ', count(DISTINCT cp.id)';
	my $visible_count_test = 'HAVING count(DISTINCT cp.id) > 0';

	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$visible_count_test = '';
		$has_copies = '' if ($ou_type == 0);
		$has_vols = '' if ($ou_type == 0);
	}

	my $rank_calc = ", sum($rank + CASE WHEN f.value ILIKE ? THEN 1 ELSE 0 END)/count(m.source)";
	$rank_calc = ', 1' if ($self->api_name =~ /unordered/o);

	my $select = <<"	SQL";
		SELECT	m.metarecord $rank_calc $visible_count
	  	  FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$asset_call_number_table cn,
			$asset_copy_table cp,
			$descendants d
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND cn.record = m.source
			$has_vols
			$has_copies
			$copies_visible
	  	  GROUP BY m.metarecord $visible_count_test
	  	  ORDER BY 2 DESC
		  $limit_clause $offset_clause
	SQL

	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $string = '%'.join('%',$fts->words).'%';
	my $recs = ($self->api_name =~ /unordered/o) ? 
			$class->db_Main->selectall_arrayref($select) :
			$class->db_Main->selectall_arrayref($select, {}, lc($string));
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	$client->respond($_) for (@$recs);
	return undef;
}

for my $class ( qw/title author subject keyword series/ ) {
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.search_fts.metarecord",
		method		=> 'search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.search_fts.metarecord.unordered",
		method		=> 'search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.search_fts.metarecord.staff",
		method		=> 'search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.search_fts.metarecord.staff.unordered",
		method		=> 'search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
}

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

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value',"$index_col");

	my $fts_where = $fts->sql_where_clause;

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE';
	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$has_vols = '' if ($ou_type == 0);
		$has_copies = '' if ($ou_type == 0);
	}

	# XXX test an "EXISTS version of descendant checking...
	my $select = <<"	SQL";
		SELECT	count(distinct  m.metarecord)
	  	  FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$asset_call_number_table cn,
			$asset_copy_table cp,
			$descendants d
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND cn.record = m.source
			$has_vols
			$has_copies
			$copies_visible
	SQL

	$log->debug("Field Search Count SQL :: [$select]",DEBUG);

	my $recs = $class->db_Main->selectrow_arrayref($select)->[0];
	
	$log->debug("Count Search yielded $recs results.",DEBUG);

	return $recs;

}
for my $class ( qw/title author subject keyword series/ ) {
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.search_fts.metarecord_count",
		method		=> 'search_class_fts_count',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.search_fts.metarecord_count.staff",
		method		=> 'search_class_fts_count',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
}


1;
