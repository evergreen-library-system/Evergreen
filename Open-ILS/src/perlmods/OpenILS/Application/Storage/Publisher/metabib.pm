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
	my $formats = shift;

	my (@types,@forms);

	if ($formats) {
		my ($t, $f) = split '-', $formats;
		@types = split '', $t;
		@forms = split '', $f;
	}

	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my $sm_table = metabib::metarecord_source_map->table;
	my $rd_table = metabib::record_descriptor->table;
	my $cn_table = asset::call_number->table;
	my $cl_table = asset::copy_location->table;
	my $cp_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $out_table = actor::org_unit_type->table;

	my $sql = <<"	SQL";
	 SELECT	*
	   FROM	(
		SELECT	rd.record,
			rd.item_type,
			rd.item_form,
	SQL

	if ($copies_visible) {
		$sql .= <<"		SQL"; 
                        sum((SELECT	count(cp.id)
	                       FROM	$cp_table cp
			       		JOIN $cs_table cs ON (cp.status = cs.id)
			       		JOIN $cl_table cl ON (cp.location = cl.id)
	                       WHERE	cn.id = cp.call_number
	                                $copies_visible
			  )) AS count
		SQL
	} else {
		$sql .= '0 AS count';
	}

	if ($copies_visible) {
		$sql .= <<"		SQL";
		  FROM	$cn_table cn,
			$sm_table sm,
			$rd_table rd
		  WHERE	rd.record = sm.source
		  	AND cn.record = rd.record
			AND sm.metarecord = ?
		SQL
	} else {
		$sql .= <<"		SQL";
		  FROM	$sm_table sm,
			$rd_table rd
		  WHERE	rd.record = sm.source
			AND sm.metarecord = ?
		SQL
	}

	$sql .= <<"	SQL";
		  GROUP BY rd.record, rd.item_type, rd.item_form
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
		) x
	SQL

	if ($copies_visible) {
		$sql .= ' WHERE x.count > 0'
	}

	if (@types) {
		$sql .= ' AND x.item_type IN ('.join(',',map{'?'}@types).')';
	}

	if (@forms) {
		$sql .= ' AND x.item_form IN ('.join(',',map{'?'}@forms).')';
	}

	my $sth = metabib::metarecord_source_map->db_Main->prepare_cached($sql);
	$sth->execute("$mr", @types, @forms);
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
	my $cl_table = asset::copy_location->table;
	my $cs_table = config::copy_status->table;
	my $out_table = actor::org_unit_type->table;
	my $descendants = "actor.org_unit_descendants(u.id)";
	my $ancestors = "actor.org_unit_ancestors(?)";

	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my $sql = <<"	SQL";
		SELECT	t.depth,
			u.id AS org_unit,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
			       		JOIN $cs_table cs ON (cp.status = cs.id)
			       		JOIN $cl_table cl ON (cp.location = cl.id)
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
			       		JOIN $cs_table cs ON (cp.status = cs.id)
			       		JOIN $cl_table cl ON (cp.location = cl.id)
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

sub multi_search_full_rec {
	my $self = shift;
	my $client = shift;

	my %args = @_;	
	my $class_join = $args{class_join} || 'AND';
	my @binds;
	my @selects;

	for my $arg (@{ $args{searches} }) {
		my $term = $$arg{term};
		my $limiters = $$arg{restrict};

		my ($index_col) = metabib::full_rec->columns('FTS');
		$index_col ||= 'value';
		my $search_table = metabib::full_rec->table;

		my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value',"$index_col");

		my $fts_where = $fts->sql_where_clause();
		my @fts_ranks = $fts->fts_rank;

		my $rank = join(' + ', @fts_ranks);

		my @wheres;
		for my $limit (@$limiters) {
			push @wheres, "( tag = ? AND subfield LIKE ? AND $fts_where )";
			push @binds, $$limit{tag}, $$limit{subfield};
 			$log->debug("Limiting query using { tag => $$limit{tag}, subfield => $$limit{subfield} }", DEBUG);
		}
		my $where = join(' OR ', @wheres);

		push @selects, "SELECT record, sum($rank) FROM $search_table WHERE $where GROUP BY 1 ORDER BY 2 DESC";

	}

	my $descendants = defined($args{depth}) ?
				"actor.org_unit_descendants($args{org_unit}, $args{depth})" :
				defined($args{depth}) ?
					"actor.org_unit_descendants($args{org_unit})" :
					"actor.org_unit";


	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;

	my $cj = ''; $cj = 'HAVING COUNT(x.record) > 1' if ($class_join eq 'AND');
	my $search_table = '(SELECT x.record, sum(x.sum) FROM (('.join(') UNION ALL (', @selects).")) x GROUP BY 1 $cj )";

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';

	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$has_copies = '' if ($ou_type == 0);
		$has_vols = '' if ($ou_type == 0);
	}

	my ($t_filter, $f_filter) = ('','');

	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		my @types = split '', $t;
		my @forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		}
		push @binds, @types, @forms;
	}


	if ($copies_visible) {
		$select = <<"		SQL";
			SELECT	m.metarecord, sum(f.sum), count(DISTINCT cp.id), CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
	  	  	FROM	$search_table f,
				$metabib_metarecord_source_map_table m,
				$asset_call_number_table cn,
				$asset_copy_table cp,
				$cs_table cs,
				$cl_table cl,
				$metabib_record_descriptor rd,
				$descendants d
	  	  	WHERE	m.source = f.record
				AND cn.record = m.source
				AND rd.record = m.source
				AND cp.status = cs.id
				AND cp.location = cl.id
				$has_vols
				$has_copies
				$copies_visible
				$t_filter
				$f_filter
	  	  	GROUP BY m.metarecord HAVING count(DISTINCT cp.id) > 0
	  	  	ORDER BY 2 DESC,3 DESC
		SQL
	} else {
		$select = <<"		SQL";
			SELECT	m.metarecord, 1, 0, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
	  	  	FROM	$search_table f,
				$metabib_metarecord_source_map_table m,
				$metabib_record_descriptor rd
	  	  	WHERE	m.source = f.record
				AND rd.record = m.source
				$t_filter
				$f_filter
	  	  	GROUP BY 1,2,3 
		SQL
	}


	$log->debug("Search SQL :: [$select]",DEBUG);

	my $recs = metabib::full_rec->db_Main->selectall_arrayref("$select;", {}, @binds);
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	$client->respond($_) for (@$recs);
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.full_rec.multi_search',
	method		=> 'multi_search_full_rec',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.metabib.full_rec.multi_search.staff',
	method		=> 'multi_search_full_rec',
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

	my (@types,@forms);
	my ($t_filter, $f_filter) = ('','');

	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}



	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'f.value', "f.$index_col");

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';

	my $visible_count = ', count(DISTINCT cp.id)';
	my $visible_count_test = 'HAVING count(DISTINCT cp.id) > 0';

	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$visible_count_test = '';
		$has_copies = '' if ($ou_type == 0);
		$has_vols = '' if ($ou_type == 0);
	}

	my $rank_calc = <<"	RANK";
		, (SUM(	$rank
			* CASE WHEN f.value ILIKE ? THEN 1.2 ELSE 1 END -- phrase order
			* CASE WHEN f.value ILIKE ? THEN 1.5 ELSE 1 END -- first word match
			* CASE WHEN f.value ~* ? THEN 2 ELSE 1 END -- only word match
		)/COUNT(m.source)), MIN(COALESCE(CHAR_LENGTH(f.value),1))
	RANK

	$rank_calc = ',1 , 1' if ($self->api_name =~ /unordered/o);

	if ($copies_visible) {
		$select = <<"		SQL";
			SELECT	m.metarecord $rank_calc $visible_count, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
	  	  	FROM	$search_table f,
				$metabib_metarecord_source_map_table m,
				$asset_call_number_table cn,
				$asset_copy_table cp,
				$cs_table cs,
				$cl_table cl,
				$metabib_record_descriptor rd,
				$descendants d
	  	  	WHERE	$fts_where
		  		AND m.source = f.source
				AND cn.record = m.source
				AND rd.record = m.source
				AND cp.status = cs.id
				AND cp.location = cl.id
				$has_vols
				$has_copies
				$copies_visible
				$t_filter
				$f_filter
	  	  	GROUP BY 1 $visible_count_test
	  	  	ORDER BY 2 DESC,3
		  	$limit_clause $offset_clause
		SQL
	} else {
		$select = <<"		SQL";
			SELECT	m.metarecord $rank_calc, 0, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
	  	  	FROM	$search_table f,
				$metabib_metarecord_source_map_table m,
				$metabib_record_descriptor rd
	  	  	WHERE	$fts_where
		  		AND m.source = f.source
				AND rd.record = m.source
				$t_filter
				$f_filter
	  	  	GROUP BY 1, 4
	  	  	ORDER BY 2 DESC,3
		  	$limit_clause $offset_clause
		SQL
	}

	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $SQLstring = join('%',$fts->words);
	my $REstring = join('\\s+',$fts->words);
	my $first_word = ($fts->words)[0].'%';
	my $recs = ($self->api_name =~ /unordered/o) ? 
			$class->db_Main->selectall_arrayref($select, {}, @types, @forms) :
			$class->db_Main->selectall_arrayref($select, {},
				'%'.lc($SQLstring).'%',			# phrase order match
				lc($first_word),			# first word match
				'^\\s*'.lc($REstring).'\\s*/?\s*$',	# full exact match
				@types, @forms
			);
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	$client->respond($_) for (map { [@$_[0,1,3,4]] } @$recs);
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
		
	my (@types,@forms);
	my ($t_filter, $f_filter) = ('','');

	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}


	(my $search_class = $self->api_name) =~ s/.*metabib.(\w+).search_fts.*/$1/o;

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'value',"$index_col");

	my $fts_where = $fts->sql_where_clause;

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';
	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$has_vols = '' if ($ou_type == 0);
		$has_copies = '' if ($ou_type == 0);
	}

	# XXX test an "EXISTS version of descendant checking...
	my $select;
	if ($copies_visible) {
		$select = <<"		SQL";
		SELECT	count(distinct  m.metarecord)
	  	  FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$asset_call_number_table cn,
			$asset_copy_table cp,
			$cs_table cs,
			$cl_table cl,
			$metabib_record_descriptor rd,
			$descendants d
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND cn.record = m.source
			AND rd.record = m.source
			AND cp.status = cs.id
			AND cp.location = cl.id
			$has_vols
			$has_copies
			$copies_visible
			$t_filter
			$f_filter
		SQL
	} else {
		$select = <<"		SQL";
		SELECT	count(distinct  m.metarecord)
	  	  FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$metabib_record_descriptor rd
	  	  WHERE	$fts_where
		  	AND m.source = f.source
			AND rd.record = m.source
			$t_filter
			$f_filter
		SQL
	}

	$log->debug("Field Search Count SQL :: [$select]",DEBUG);

	my $recs = $class->db_Main->selectrow_arrayref($select, {}, @types, @forms)->[0];
	
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





# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub new_search_class_fts {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $term = $args{term};
	my $ou = $args{org_unit};
	my $ou_type = $args{depth};
	my $limit = $args{limit};
	my $offset = $args{offset} ||= 0;

	my $limit_clause = '';
	my $offset_clause = '';

	$limit_clause = "LIMIT $limit" if (defined $limit and int($limit) > 0);
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

	my (@types,@forms);
	my ($t_filter, $f_filter) = ('','');

	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}



	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'f.value', "f.$index_col");

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';

	my $visible_count = ', count(DISTINCT cp.id)';
	my $visible_count_test = 'HAVING count(DISTINCT cp.id) > 0';

	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$visible_count_test = '';
		$has_copies = '' if ($ou_type == 0);
		$has_vols = '' if ($ou_type == 0);
	}

	my $rank_calc = <<"	RANK";
		, (SUM(	$rank
			* CASE WHEN f.value ILIKE ? THEN 1.2 ELSE 1 END -- phrase order
			* CASE WHEN f.value ILIKE ? THEN 1.5 ELSE 1 END -- first word match
			* CASE WHEN f.value ~* ? THEN 2 ELSE 1 END -- only word match
		)/COUNT(m.source)), MIN(COALESCE(CHAR_LENGTH(f.value),1))
	RANK

	$rank_calc = ',1 , 1' if ($self->api_name =~ /unordered/o);

	if ($copies_visible) {
		$select = <<"		SQL";
			SELECT	m.metarecord $rank_calc $visible_count, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
	  	  	FROM	$search_table f,
				$metabib_metarecord_source_map_table m,
				$asset_call_number_table cn,
				$asset_copy_table cp,
				$cs_table cs,
				$cl_table cl,
				$metabib_record_descriptor rd,
				$descendants d
	  	  	WHERE	$fts_where
		  		AND m.source = f.source
				AND cn.record = m.source
				AND rd.record = m.source
				AND cp.status = cs.id
				AND cp.location = cl.id
				$has_vols
				$has_copies
				$copies_visible
				$t_filter
				$f_filter
	  	  	GROUP BY m.metarecord $visible_count_test
	  	  	ORDER BY 2 DESC,3
		SQL
	} else {
		$select = <<"		SQL";
			SELECT	m.metarecord $rank_calc, 0, CASE WHEN COUNT(DISTINCT m.source) = 1 THEN MAX(m.source) ELSE MAX(0) END
	  	  	FROM	$search_table f,
				$metabib_metarecord_source_map_table m,
				$metabib_record_descriptor rd
	  	  	WHERE	$fts_where
		  		AND m.source = f.source
				AND rd.record = m.source
				$t_filter
				$f_filter
	  	  	GROUP BY 1, 4 
	  	  	ORDER BY 2 DESC,3
		SQL
	}

	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $SQLstring = join('%',$fts->words);
	my $REstring = join('\\s+',$fts->words);
	my $first_word = ($fts->words)[0].'%';
	my $recs = ($self->api_name =~ /unordered/o) ? 
			$class->db_Main->selectall_arrayref($select, {}, @types, @forms) :
			$class->db_Main->selectall_arrayref($select, {},
				'%'.lc($SQLstring).'%',			# phrase order match
				lc($first_word),			# first word match
				'^\\s*'.lc($REstring).'\\s*/?\s*$',	# full exact match
				@types, @forms
			);
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	my $count = scalar(@$recs);
	$client->respond($_) for (map { [@$_[0,1,3],$count,$$_[4]] } @$recs[$offset .. $offset + $limit]);
	return undef;
}

for my $class ( qw/title author subject keyword series/ ) {
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.new_search_fts.metarecord",
		method		=> 'new_search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.new_search_fts.metarecord.unordered",
		method		=> 'new_search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.new_search_fts.metarecord.staff",
		method		=> 'new_search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.new_search_fts.metarecord.staff.unordered",
		method		=> 'new_search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
}


my $_cdbi = {	title	=> "metabib::title_field_entry",
		author	=> "metabib::author_field_entry",
		subject	=> "metabib::subject_field_entry",
		keyword	=> "metabib::keyword_field_entry",
		series	=> "metabib::series_field_entry",
};



1;
