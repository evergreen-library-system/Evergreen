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

sub ordered_records_from_metarecord {
	my $self = shift;
	my $client = shift;
	my $mr = shift;
	my $formats = shift;
	my $org = shift || 1;
	my $depth = shift;

	my (@types,@forms);

	if ($formats) {
		my ($t, $f) = split '-', $formats;
		@types = split '', $t;
		@forms = split '', $f;
	}

	my $descendants =
		defined($depth) ?
			"actor.org_unit_descendants($org, $depth)" :
			"actor.org_unit_descendants($org)" ;


	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my $sm_table = metabib::metarecord_source_map->table;
	my $rd_table = metabib::record_descriptor->table;
	my $fr_table = metabib::full_rec->table;
	my $cn_table = asset::call_number->table;
	my $cl_table = asset::copy_location->table;
	my $cp_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $src_table = config::bib_source->table;
	my $out_table = actor::org_unit_type->table;
	my $br_table = biblio::record_entry->table;

	my $sql = <<"	SQL";
		SELECT	record,
			item_type,
			item_form,
			quality,
			FIRST(COALESCE(LTRIM(SUBSTR( value, COALESCE(SUBSTRING(ind2 FROM '\\\\d+'),'0')::INT )),'zzzzzzzz')) AS title
		FROM	(
			SELECT	rd.record,
				rd.item_type,
				rd.item_form,
				br.quality,
				fr.tag,
				fr.subfield,
				fr.value,
				fr.ind2
	SQL

	if ($copies_visible) {
		$sql .= <<"		SQL";
	  		  FROM	$sm_table sm,
				$br_table br,
				$fr_table fr,
				$rd_table rd
		  	  WHERE	rd.record = sm.source
				AND fr.record = sm.source
		  		AND br.id = sm.source
				AND sm.metarecord = ?
                        	AND (EXISTS ((SELECT	1
						FROM	$cp_table cp
							JOIN $cn_table cn ON (cp.call_number = cn.id)
				       			JOIN $cs_table cs ON (cp.status = cs.id)
				       			JOIN $cl_table cl ON (cp.location = cl.id)
							JOIN $descendants d ON (cp.circ_lib = d.id)
						WHERE	cn.record = sm.source
		                                	$copies_visible
						LIMIT 1))
					OR EXISTS ((
					    SELECT	1
					      FROM	$src_table src
					      WHERE	src.id = br.source
					      		AND src.transcendant IS TRUE))
				)
					  
		SQL
	} else {
		$sql .= <<"		SQL";
			  FROM	$sm_table sm
				JOIN $br_table br ON (sm.source = br.id)
				JOIN $fr_table fr ON (fr.record = br.id)
				JOIN $rd_table rd ON (rd.record = br.id)
			  WHERE	sm.metarecord = ?
				AND ((	EXISTS (
						SELECT	1
						  FROM	$cp_table cp,
							$cn_table cn,
							$descendants d
						  WHERE	cn.record = br.id
							AND cn.deleted = FALSE
							AND cp.deleted = FALSE
							AND cp.circ_lib = d.id
							AND cn.id = cp.call_number
						  LIMIT 1
					) OR NOT EXISTS (
						SELECT	1
						  FROM	$cp_table cp,
							$cn_table cn
						  WHERE	cn.record = br.id
							AND cn.deleted = FALSE
							AND cp.deleted = FALSE
							AND cn.id = cp.call_number
						  LIMIT 1
					))
					OR EXISTS ((
					    SELECT	1
					      FROM	$src_table src
					      WHERE	src.id = br.source
					      		AND src.transcendant IS TRUE))
				)
		SQL
	}

	if (@types) {
		$sql .= '				AND rd.item_type IN ('.join(',',map{'?'}@types).')';
	}

	if (@forms) {
		$sql .= '				AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
	}



	$sql .= <<"	SQL";
	  		  OFFSET 0
			) AS x
	  WHERE	tag = '245'
	  	AND subfield = 'a'
	  GROUP BY record, item_type, item_form, quality
	  ORDER BY
		CASE
			WHEN item_type IS NULL -- default
				THEN 0
			WHEN item_type = '' -- default
				THEN 0
			WHEN item_type IN ('a','t') -- books
				THEN 1
			WHEN item_type = 'g' -- movies
				THEN 2
			WHEN item_type IN ('i','j') -- sound recordings
				THEN 3
			WHEN item_type = 'm' -- software
				THEN 4
			WHEN item_type = 'k' -- images
				THEN 5
			WHEN item_type IN ('e','f') -- maps
				THEN 6
			WHEN item_type IN ('o','p') -- mixed
				THEN 7
			WHEN item_type IN ('c','d') -- music
				THEN 8
			WHEN item_type = 'r' -- 3d
				THEN 9
		END,
		title ASC,
		quality DESC
	SQL

	my $ids = metabib::metarecord_source_map->db_Main->selectcol_arrayref($sql, {}, "$mr", @types, @forms);
	return $ids if ($self->api_name =~ /atomic$/o);

	$client->respond( $_ ) for ( @$ids );
	return undef;

}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.ordered.metabib.metarecord.records',
	method		=> 'ordered_records_from_metarecord',
	api_level	=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.ordered.metabib.metarecord.records.staff',
	method		=> 'ordered_records_from_metarecord',
	api_level	=> 1,
	cachable	=> 1,
);

__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.ordered.metabib.metarecord.records.atomic',
	method		=> 'ordered_records_from_metarecord',
	api_level	=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.ordered.metabib.metarecord.records.staff.atomic',
	method		=> 'ordered_records_from_metarecord',
	api_level	=> 1,
	cachable	=> 1,
);

sub isxn_search {
	my $self = shift;
	my $client = shift;
	my $isxn = shift;

	my $tag = ($self->api_name =~ /isbn/o) ? '020' : '022';

	my $fr_table = metabib::full_rec->table;

	my $sql = <<"	SQL";
		SELECT	record
		  FROM	$fr_table
		  WHERE	tag = ?
			AND value LIKE ?
	SQL

	my $list = metabib::metarecord_source_map->db_Main->selectcol_arrayref($sql, {}, $tag, "$isxn%");
	$client->respond($_) for (@$list);
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.id_list.biblio.record_entry.search.isbn',
	method		=> 'isxn_search',
	api_level	=> 1,
	stream		=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.id_list.biblio.record_entry.search.issn',
	method		=> 'isxn_search',
	api_level	=> 1,
	stream		=> 1,
);

sub metarecord_copy_count {
	my $self = shift;
	my $client = shift;

	my %args = @_;

	my $sm_table = metabib::metarecord_source_map->table;
	my $rd_table = metabib::record_descriptor->table;
	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;
	my $cl_table = asset::copy_location->table;
	my $cs_table = config::copy_status->table;
	my $out_table = actor::org_unit_type->table;
	my $descendants = "actor.org_unit_descendants(u.id)";
	my $ancestors = "actor.org_unit_ancestors(?)";

	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

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

	my $sql = <<"	SQL";
		SELECT	t.depth,
			u.id AS org_unit,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $rd_table rd ON (cn.record = rd.record)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
			       		JOIN $cs_table cs ON (cp.status = cs.id)
			       		JOIN $cl_table cl ON (cp.location = cl.id)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE r.metarecord = ?
				  	AND cn.deleted IS FALSE
				  	AND cp.deleted IS FALSE
				  	$copies_visible
					$t_filter
					$f_filter
				)
			) AS count,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $rd_table rd ON (cn.record = rd.record)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
			       		JOIN $cs_table cs ON (cp.status = cs.id)
			       		JOIN $cl_table cl ON (cp.location = cl.id)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE r.metarecord = ?
				  	AND cp.status = 0
				  	AND cn.deleted IS FALSE
				  	AND cp.deleted IS FALSE
					$copies_visible
					$t_filter
					$f_filter
				)
			) AS available,
			sum(
				(SELECT count(cp.id)
				  FROM  $sm_table r
					JOIN $cn_table cn ON (cn.record = r.source)
					JOIN $rd_table rd ON (cn.record = rd.record)
					JOIN $cp_table cp ON (cn.id = cp.call_number)
			       		JOIN $cs_table cs ON (cp.status = cs.id)
			       		JOIN $cl_table cl ON (cp.location = cl.id)
				  WHERE r.metarecord = ?
				  	AND cn.deleted IS FALSE
				  	AND cp.deleted IS FALSE
					AND cp.opac_visible IS TRUE
					AND cs.holdable IS TRUE
					AND cl.opac_visible IS TRUE
					$t_filter
					$f_filter
				)
			) AS unshadow

		  FROM  $ancestors u
			JOIN $out_table t ON (u.ou_type = t.id)
		  GROUP BY 1,2
	SQL

	my $sth = metabib::metarecord_source_map->db_Main->prepare_cached($sql);
	$sth->execute(	''.$args{metarecord},
			@types, 
			@forms,
			''.$args{metarecord},
			@types, 
			@forms,
			''.$args{metarecord},
			@types, 
			@forms,
			''.$args{org_unit}, 
	); 

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

sub biblio_multi_search_full_rec {
	my $self = shift;
	my $client = shift;

	my %args = @_;	
	my $class_join = $args{class_join} || 'AND';
	my $limit = $args{limit} || 100;
	my $offset = $args{offset} || 0;
	my $sort = $args{'sort'};
	my $sort_dir = $args{sort_dir} || 'DESC';

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

		push @selects, "SELECT id, record, $rank as sum FROM $search_table WHERE $where";

	}

	my $descendants = defined($args{depth}) ?
				"actor.org_unit_descendants($args{org_unit}, $args{depth})" :
				"actor.org_unit_descendants($args{org_unit})" ;


	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_full_rec = metabib::full_rec->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;
	my $br_table = biblio::record_entry->table;

	my $cj = 'HAVING COUNT(x.id) = ' . scalar(@selects) if ($class_join eq 'AND');
	my $search_table =
		'(SELECT x.record, sum(x.sum) FROM (('.
			join(') UNION ALL (', @selects).
			")) x GROUP BY 1 $cj ORDER BY 2 DESC )";

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE AND cl.opac_visible IS TRUE';

	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$has_copies = '' if ($ou_type == 0);
		$has_vols = '' if ($ou_type == 0);
	}

	my ($t_filter, $f_filter) = ('','');
	my ($a_filter, $l_filter, $lf_filter) = ('','','');

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		my @aud = @$a;
			
		$a_filter = ' AND rd.audience IN ('.join(',',map{'?'}@aud).')';
		push @binds, @aud;
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		my @lang = @$l;

		$l_filter = ' AND rd.item_lang IN ('.join(',',map{'?'}@lang).')';
		push @binds, @lang;
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		my @lit_form = @$f;

		$lf_filter = ' AND rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
		push @binds, @lit_form;
	}

	if (my $f = $args{item_form}) {
		$f = [$f] if (!ref($f));
		my @forms = @$f;

		$f_filter = ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		push @binds, @forms;
	}

	if (my $t = $args{item_type}) {
		$t = [$t] if (!ref($t));
		my @types = @$t;

		$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		push @binds, @types;
	}


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

	my $relevance = 'sum(f.sum)';
	$relevance = 1 if (!$copies_visible);

	my $rank = $relevance;
	if (lc($sort) eq 'pubdate') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(frp.value FROM '\\\\d+'),'9999')::INT
				  FROM	$metabib_full_rec frp
				  WHERE	frp.record = f.record
				  	AND frp.tag = '260'
					AND frp.subfield = 'c'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'create_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = f.record)) )
		RANK
	} elsif (lc($sort) eq 'edit_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = f.record)) )
		RANK
	} elsif (lc($sort) eq 'title') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM '\\\\d+'),'0')::INT )),'zzzzzzzz')
				  FROM	$metabib_full_rec frt
				  WHERE	frt.record = f.record
				  	AND frt.tag = '245'
					AND frt.subfield = 'a'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'author') {
		$rank = <<"		RANK";
			( FIRST((
				SELECT	COALESCE(LTRIM(fra.value),'zzzzzzzz')
				  FROM	$metabib_full_rec fra
				  WHERE	fra.record = f.record
				  	AND fra.tag LIKE '1%'
					AND fra.subfield = 'a'
				  ORDER BY fra.tag::text::int
				  LIMIT 1
			)) )
		RANK
	} else {
		$sort = undef;
	}


	if ($copies_visible) {
		$select = <<"		SQL";
			SELECT	f.record, $relevance, count(DISTINCT cp.id), $rank
	  	  	FROM	$search_table f,
				$asset_call_number_table cn,
				$asset_copy_table cp,
				$cs_table cs,
				$cl_table cl,
				$br_table br,
				$metabib_record_descriptor rd,
				$descendants d
	  	  	WHERE	br.id = f.record
				AND cn.record = f.record
				AND rd.record = f.record
				AND cp.status = cs.id
				AND cp.location = cl.id
				AND br.deleted IS FALSE
				AND cn.deleted IS FALSE
				AND cp.deleted IS FALSE
				$has_vols
				$has_copies
				$copies_visible
				$t_filter
				$f_filter
				$a_filter
				$l_filter
				$lf_filter
	  	  	GROUP BY f.record HAVING count(DISTINCT cp.id) > 0
	  	  	ORDER BY 4 $sort_dir,3 DESC
		SQL
	} else {
		$select = <<"		SQL";
			SELECT	f.record, 1, 1, $rank
	  	  	FROM	$search_table f,
				$br_table br,
				$metabib_record_descriptor rd
	  	  	WHERE	br.id = f.record
				AND rd.record = f.record
				AND br.deleted IS FALSE
				$t_filter
				$f_filter
				$a_filter
				$l_filter
				$lf_filter
	  	  	GROUP BY 1,2,3 
	  	  	ORDER BY 4 $sort_dir
		SQL
	}


	$log->debug("Search SQL :: [$select]",DEBUG);

	my $recs = metabib::full_rec->db_Main->selectall_arrayref("$select;", {}, @binds);
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	my $max = 0;
	$max = 1 if (!@$recs);
	for (@$recs) {
		$max = $$_[1] if ($$_[1] > $max);
	}

	my $count = @$recs;
	for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
		next unless ($$rec[0]);
		my ($rid,$rank,$junk,$skip) = @$rec;
		$client->respond( [$rid, sprintf('%0.3f',$rank/$max), $count] );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.biblio.full_rec.multi_search',
	method		=> 'biblio_multi_search_full_rec',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.biblio.full_rec.multi_search.staff',
	method		=> 'biblio_multi_search_full_rec',
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
			$metabib_metarecord_source_map_table mr,
			$asset_call_number_table cn,
			$asset_copy_table cp,
			$cs_table cs,
			$cl_table cl,
			$metabib_record_descriptor rd,
			$descendants d
	  	  WHERE	$fts_where
		  	AND mr.source = f.source
			AND mr.metarecord = m.metarecord
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
			$metabib_metarecord_source_map_table mr,
			$metabib_record_descriptor rd
	  	  WHERE	$fts_where
		  	AND mr.source = f.source
			AND mr.metarecord = m.metarecord
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
sub postfilter_search_class_fts {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $term = $args{term};
	my $sort = $args{'sort'};
	my $sort_dir = $args{sort_dir} || 'DESC';
	my $ou = $args{org_unit};
	my $ou_type = $args{depth};
	my $limit = $args{limit} || 10;
	my $visiblity_limit = $args{visiblity_limit} || 5000;
	my $offset = $args{offset} || 0;

	my $outer_limit = 1000;

	my $limit_clause = '';
	my $offset_clause = '';

	$limit_clause = "LIMIT $outer_limit";
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

	my (@types,@forms,@lang,@aud,@lit_form);
	my ($t_filter, $f_filter) = ('','');
	my ($a_filter, $l_filter, $lf_filter) = ('','','');
	my ($ot_filter, $of_filter) = ('','');
	my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		@aud = @$a;
			
		$a_filter = ' AND rd.audience IN ('.join(',',map{'?'}@aud).')';
		$oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		@lang = @$l;

		$l_filter = ' AND rd.item_lang IN ('.join(',',map{'?'}@lang).')';
		$ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		@lit_form = @$f;

		$lf_filter = ' AND rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
		$olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
	}

	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
			$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
			$of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}


	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $class = $self->{cdbi};
	my $search_table = $class->table;

	my $metabib_full_rec = metabib::full_rec->table;
	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;
	my $br_table = biblio::record_entry->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'f.value', "f.$index_col");

	my $SQLstring = join('%',map { lc($_) } $fts->words);
	my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
	my $first_word = lc(($fts->words)[0]).'%';

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my %bonus = ();
	$bonus{'metabib::keyword_field_entry'} = [ { 'CASE WHEN f.value ILIKE ? THEN 1.2 ELSE 1 END' => $SQLstring } ];
	$bonus{'metabib::title_field_entry'} =
		$bonus{'metabib::series_field_entry'} = [
			{ 'CASE WHEN f.value ILIKE ? THEN 1.5 ELSE 1 END' => $first_word },
			{ 'CASE WHEN f.value ~* ? THEN 2 ELSE 1 END' => $REstring },
			@{ $bonus{'metabib::keyword_field_entry'} }
		];

	my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$class} };
	$bonus_list ||= '1';

	my @bonus_values = map { values %$_ } @{ $bonus{$class} };

	my $relevance = join(' + ', @fts_ranks);
	$relevance = <<"	RANK";
			(SUM( ( $relevance )  * ( $bonus_list ) )/COUNT(m.source))
	RANK

	my $rank = $relevance;
	if (lc($sort) eq 'pubdate') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(frp.value FROM '\\\\d+'),'9999')::INT
				  FROM	$metabib_full_rec frp
				  WHERE	frp.record = mr.master_record
				  	AND frp.tag = '260'
					AND frp.subfield = 'c'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'create_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
		RANK
	} elsif (lc($sort) eq 'edit_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
		RANK
	} elsif (lc($sort) eq 'title') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM '\\\\d+'),'0')::INT )),'zzzzzzzz')
				  FROM	$metabib_full_rec frt
				  WHERE	frt.record = mr.master_record
				  	AND frt.tag = '245'
					AND frt.subfield = 'a'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'author') {
		$rank = <<"		RANK";
			( FIRST((
				SELECT	COALESCE(LTRIM(fra.value),'zzzzzzzz')
				  FROM	$metabib_full_rec fra
				  WHERE	fra.record = mr.master_record
				  	AND fra.tag LIKE '1%'
					AND fra.subfield = 'a'
				  ORDER BY fra.tag::text::int
				  LIMIT 1
			)) )
		RANK
	} else {
		$sort = undef;
	}

	my $select = <<"	SQL";
		SELECT	m.metarecord,
			$relevance,
			CASE WHEN COUNT(DISTINCT smrs.source) = 1 THEN MIN(m.source) ELSE 0 END,
			$rank
  	  	FROM	$search_table f,
			$metabib_metarecord_source_map_table m,
			$metabib_metarecord_source_map_table smrs,
			$metabib_metarecord mr,
			$metabib_record_descriptor rd
  	  	WHERE	$fts_where
	  		AND smrs.metarecord = mr.id
	  		AND m.source = f.source
	  		AND m.metarecord = mr.id
			AND rd.record = smrs.source
			$t_filter
			$f_filter
			$a_filter
			$l_filter
			$lf_filter
  	  	GROUP BY m.metarecord
  	  	ORDER BY 4 $sort_dir, MIN(COALESCE(CHAR_LENGTH(f.value),1))
		LIMIT $visiblity_limit
	SQL

	if (0) {
		$select = <<"		SQL";

			SELECT	DISTINCT s.*
			  FROM	$asset_call_number_table cn,
				$metabib_metarecord_source_map_table mrs,
				$asset_copy_table cp,
				$cs_table cs,
				$cl_table cl,
				$br_table br,
				$descendants d,
				$metabib_record_descriptor ord,
				($select) s
			  WHERE	mrs.metarecord = s.metarecord
				AND br.id = mrs.source
				AND cn.record = mrs.source
				AND cp.status = cs.id
				AND cp.location = cl.id
				AND cn.owning_lib = d.id
				AND cp.call_number = cn.id
				AND cp.opac_visible IS TRUE
				AND cs.holdable IS TRUE
				AND cl.opac_visible IS TRUE
				AND br.active IS TRUE
				AND br.deleted IS FALSE
				AND ord.record = mrs.source
				$ot_filter
				$of_filter
				$oa_filter
				$ol_filter
				$olf_filter
			  ORDER BY 4 $sort_dir
		SQL
	} elsif ($self->api_name !~ /staff/o) {
		$select = <<"		SQL";

			SELECT	DISTINCT s.*
			  FROM	($select) s
			  WHERE	EXISTS (
			  	SELECT	1
				  FROM	$asset_call_number_table cn,
					$metabib_metarecord_source_map_table mrs,
					$asset_copy_table cp,
					$cs_table cs,
					$cl_table cl,
					$br_table br,
					$descendants d,
					$metabib_record_descriptor ord
				
				  WHERE	mrs.metarecord = s.metarecord
					AND br.id = mrs.source
					AND cn.record = mrs.source
					AND cp.status = cs.id
					AND cp.location = cl.id
					AND cn.owning_lib = d.id
					AND cp.call_number = cn.id
					AND cp.opac_visible IS TRUE
					AND cs.holdable IS TRUE
					AND cl.opac_visible IS TRUE
					AND br.active IS TRUE
					AND br.deleted IS FALSE
					AND ord.record = mrs.source
					$ot_filter
					$of_filter
					$oa_filter
					$ol_filter
					$olf_filter
				  LIMIT 1
				)
			  ORDER BY 4 $sort_dir
		SQL
	} else {
		$select = <<"		SQL";

			SELECT	DISTINCT s.*
			  FROM	($select) s
			  WHERE	EXISTS (
			  	SELECT	1
				  FROM	$asset_call_number_table cn,
					$metabib_metarecord_source_map_table mrs,
					$br_table br,
					$descendants d,
					$metabib_record_descriptor ord
				
				  WHERE	mrs.metarecord = s.metarecord
					AND br.id = mrs.source
					AND cn.record = mrs.source
					AND cn.owning_lib = d.id
					AND br.deleted IS FALSE
					AND ord.record = mrs.source
					$ot_filter
					$of_filter
					$oa_filter
					$ol_filter
					$olf_filter
				  LIMIT 1
				)
				OR NOT EXISTS (
				SELECT	1
				  FROM	$asset_call_number_table cn,
					$metabib_metarecord_source_map_table mrs,
					$metabib_record_descriptor ord
				  WHERE	mrs.metarecord = s.metarecord
					AND cn.record = mrs.source
					AND ord.record = mrs.source
					$ot_filter
					$of_filter
					$oa_filter
					$ol_filter
					$olf_filter
				  LIMIT 1
				)
			  ORDER BY 4 $sort_dir
		SQL
	}


	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $recs = $class->db_Main->selectall_arrayref(
			$select, {},
			(@bonus_values > 0 ? @bonus_values : () ),
			( (!$sort && @bonus_values > 0) ? @bonus_values : () ),
			@types, @forms, @aud, @lang, @lit_form,
			@types, @forms, @aud, @lang, @lit_form,
			($self->api_name =~ /staff/o ? (@types, @forms, @aud, @lang, @lit_form) : () ) );
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	my $max = 0;
	$max = 1 if (!@$recs);
	for (@$recs) {
		$max = $$_[1] if ($$_[1] > $max);
	}

	my $count = scalar(@$recs);
	for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
		my ($mrid,$rank,$skip) = @$rec;
		$client->respond( [$mrid, sprintf('%0.3f',$rank/$max), $skip, $count] );
	}
	return undef;
}

for my $class ( qw/title author subject keyword series/ ) {
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.post_filter.search_fts.metarecord",
		method		=> 'postfilter_search_class_fts',
		api_level	=> 1,
		stream		=> 1,
		cdbi		=> "metabib::${class}_field_entry",
		cachable	=> 1,
	);
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.metabib.$class.post_filter.search_fts.metarecord.staff",
		method		=> 'postfilter_search_class_fts',
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

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub postfilter_search_multi_class_fts {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $sort = $args{'sort'};
	my $sort_dir = $args{sort_dir} || 'DESC';
	my $ou = $args{org_unit};
	my $ou_type = $args{depth};
	my $limit = $args{limit} || 10;;
	my $visiblity_limit = $args{visiblity_limit} || 5000;;
	my $offset = $args{offset} || 0;

	if (!$ou) {
		$ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
	}

	if (!defined($args{org_unit})) {
		die "No target organizational unit passed to ".$self->api_name;
	}

	if (! scalar( keys %{$args{searches}} )) {
		die "No search arguments were passed to ".$self->api_name;
	}

	my $outer_limit = 1000;

	my $limit_clause = '';
	my $offset_clause = '';

	$limit_clause = "LIMIT $outer_limit";
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

	my (@types,@forms,@lang,@aud,@lit_form);
	my ($t_filter, $f_filter) = ('','');
	my ($a_filter, $l_filter, $lf_filter) = ('','','');
	my ($ot_filter, $of_filter) = ('','');
	my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		@aud = @$a;
			
		$a_filter = ' AND rd.audience IN ('.join(',',map{'?'}@aud).')';
		$oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		@lang = @$l;

		$l_filter = ' AND rd.item_lang IN ('.join(',',map{'?'}@lang).')';
		$ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		@lit_form = @$f;

		$lf_filter = ' AND rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
		$olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
	}

	if (my $f = $args{item_form}) {
		$f = [$f] if (!ref($f));
		@forms = @$f;

		$f_filter = ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		$of_filter = ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
	}

	if (my $t = $args{item_type}) {
		$t = [$t] if (!ref($t));
		@types = @$t;

		$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
	}


	# XXX legacy format and item type support
	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
			$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
			$of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}



	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $search_table_list = '';
	my $fts_list = '';
	my $join_table_list = '';
	my @rank_list;

	my @bonus_lists;
	my @bonus_values;
	my $prev_search_class;
	my $curr_search_class;
	for my $search_class (sort keys %{$args{searches}}) {
		$prev_search_class = $curr_search_class if ($curr_search_class);

		$curr_search_class = $search_class;

		my $class = $_cdbi->{$search_class};
		my $search_table = $class->table;

		my ($index_col) = $class->columns('FTS');
		$index_col ||= 'value';

		
		my $fts = OpenILS::Application::Storage::FTS->compile($args{searches}{$search_class}{term}, $search_class.'.value', "$search_class.$index_col");

		my $fts_where = $fts->sql_where_clause;
		my @fts_ranks = $fts->fts_rank;

		my $SQLstring = join('%',map { lc($_) } $fts->words);
		my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
		my $first_word = lc(($fts->words)[0]).'%';

		my $rank = join(' + ', @fts_ranks);

		my %bonus = ();
		$bonus{'keyword'} = [ { "CASE WHEN $search_class.value LIKE ? THEN 10 ELSE 1 END" => $SQLstring } ];

		$bonus{'series'} = [
			{ "CASE WHEN $search_class.value LIKE ? THEN 1.5 ELSE 1 END" => $first_word },
			{ "CASE WHEN $search_class.value ~ ? THEN 20 ELSE 1 END" => $REstring },
		];

		$bonus{'title'} = [ @{ $bonus{'series'} }, @{ $bonus{'keyword'} } ];

		my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$search_class} };
		$bonus_list ||= '1';

		push @bonus_lists, $bonus_list;
		push @bonus_values, map { values %$_ } @{ $bonus{$search_class} };


		#---------------------

		$search_table_list .= "$search_table $search_class, ";
		push @rank_list,$rank;
		$fts_list .= " AND $fts_where AND m.source = $search_class.source";

		if ($prev_search_class) {
			$join_table_list .= " AND $prev_search_class.source = $curr_search_class.source";
		}
	}

	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_full_rec = metabib::full_rec->table;
	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;
	my $br_table = biblio::record_entry->table;
	my $source_table = config::bib_source->table;

	my $bonuses = join (' * ', @bonus_lists);
	my $relevance = join (' + ', @rank_list);
	$relevance = "SUM( ($relevance) * ($bonuses) )/COUNT(DISTINCT smrs.source)";


	my $secondary_sort = <<"	SORT";
		( FIRST ((
			SELECT	COALESCE(LTRIM(SUBSTR( sfrt.value, COALESCE(SUBSTRING(sfrt.ind2 FROM '\\\\d+'),'0')::INT )),'zzzzzzzz')
			  FROM	$metabib_full_rec sfrt,
				$metabib_metarecord mr
			  WHERE	sfrt.record = mr.master_record
			  	AND sfrt.tag = '245'
				AND sfrt.subfield = 'a'
			  LIMIT 1
		)) )
	SORT

	my $rank = $relevance;
	if (lc($sort) eq 'pubdate') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(frp.value FROM '\\\\d+'),'9999')::INT
				  FROM	$metabib_full_rec frp
				  WHERE	frp.record = mr.master_record
				  	AND frp.tag = '260'
					AND frp.subfield = 'c'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'create_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
		RANK
	} elsif (lc($sort) eq 'edit_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = mr.master_record)) )
		RANK
	} elsif (lc($sort) eq 'title') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM '\\\\d+'),'0')::INT )),'zzzzzzzz')
				  FROM	$metabib_full_rec frt
				  WHERE	frt.record = mr.master_record
				  	AND frt.tag = '245'
					AND frt.subfield = 'a'
				  LIMIT 1
			)) )
		RANK
		$secondary_sort = <<"		SORT";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(sfrp.value FROM '\\\\d+'),'9999')::INT
				  FROM	$metabib_full_rec sfrp
				  WHERE	sfrp.record = mr.master_record
				  	AND sfrp.tag = '260'
					AND sfrp.subfield = 'c'
				  LIMIT 1
			)) )
		SORT
	} elsif (lc($sort) eq 'author') {
		$rank = <<"		RANK";
			( FIRST((
				SELECT	COALESCE(LTRIM(fra.value),'zzzzzzzz')
				  FROM	$metabib_full_rec fra
				  WHERE	fra.record = mr.master_record
				  	AND fra.tag LIKE '1%'
					AND fra.subfield = 'a'
				  ORDER BY fra.tag::text::int
				  LIMIT 1
			)) )
		RANK
	} else {
		push @bonus_values, @bonus_values;
		$sort = undef;
	}


	my $select = <<"	SQL";
		SELECT	m.metarecord,
			$relevance,
			CASE WHEN COUNT(DISTINCT smrs.source) = 1 THEN FIRST(m.source) ELSE 0 END,
			$rank,
			$secondary_sort
  	  	FROM	$search_table_list
			$metabib_metarecord mr,
			$metabib_metarecord_source_map_table m,
			$metabib_metarecord_source_map_table smrs
	  	WHERE	m.metarecord = smrs.metarecord 
			AND mr.id = m.metarecord
  	  		$fts_list
			$join_table_list
  	  	GROUP BY m.metarecord
  	  	-- ORDER BY 4 $sort_dir
		LIMIT $visiblity_limit
	SQL

	if ($self->api_name !~ /staff/o) {
		$select = <<"		SQL";

			SELECT	s.*
			  FROM	($select) s
			  WHERE	EXISTS (
			  	SELECT	1
				  FROM	$asset_call_number_table cn,
					$metabib_metarecord_source_map_table mrs,
					$asset_copy_table cp,
					$cs_table cs,
					$cl_table cl,
					$br_table br,
					$descendants d,
					$metabib_record_descriptor ord
				  WHERE	mrs.metarecord = s.metarecord
					AND br.id = mrs.source
					AND cn.record = mrs.source
					AND cp.status = cs.id
					AND cp.location = cl.id
					AND cn.owning_lib = d.id
					AND cp.call_number = cn.id
					AND cp.opac_visible IS TRUE
					AND cs.holdable IS TRUE
					AND cl.opac_visible IS TRUE
					AND br.active IS TRUE
					AND br.deleted IS FALSE
					AND cp.deleted IS FALSE
					AND cn.deleted IS FALSE
					AND ord.record = mrs.source
					$ot_filter
					$of_filter
					$oa_filter
					$ol_filter
					$olf_filter
				  LIMIT 1
			  	)
				OR EXISTS (
				SELECT	1
				  FROM	$br_table br,
					$metabib_metarecord_source_map_table mrs,
					$source_table src
				  WHERE	mrs.metarecord = s.metarecord
					AND br.id = mrs.source
					AND br.source = src.id
					AND src.transcendant IS TRUE
				)
			  ORDER BY 4 $sort_dir, 5
		SQL
	} else {
		$select = <<"		SQL";

			SELECT	DISTINCT s.*
			  FROM	($select) s,
				$metabib_metarecord_source_map_table omrs,
				$metabib_record_descriptor ord
			  WHERE	omrs.metarecord = s.metarecord
				AND ord.record = omrs.source
			  	AND (	EXISTS (
					  	SELECT	1
						  FROM	$asset_call_number_table cn,
							$descendants d,
							$br_table br
						  WHERE	br.id = omrs.source
							AND cn.record = omrs.source
							AND cn.owning_lib = d.id
							AND br.deleted IS FALSE
							AND cn.deleted IS FALSE
						  LIMIT 1
					)
					OR NOT EXISTS (
						SELECT	1
						  FROM	$asset_call_number_table cn
						  WHERE	cn.record = omrs.source
							AND cn.deleted IS FALSE
						  LIMIT 1
					)
					OR EXISTS (
					SELECT	1
					  FROM	$br_table br,
						$metabib_metarecord_source_map_table mrs,
						$source_table src
					  WHERE	mrs.metarecord = s.metarecord
						AND br.id = mrs.source
						AND br.source = src.id
						AND src.transcendant IS TRUE
					)
				)
				$ot_filter
				$of_filter
				$oa_filter
				$ol_filter
				$olf_filter

			  ORDER BY 4 $sort_dir, 5
		SQL
	}


	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $recs = $_cdbi->{title}->db_Main->selectall_arrayref(
			$select, {},
			@bonus_values,
			@types, @forms, @aud, @lang, @lit_form,
			# @types, @forms, @aud, @lang, @lit_form,
			# ($self->api_name =~ /staff/o ? (@types, @forms, @aud, @lang, @lit_form) : () )
	);
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	my $max = 0;
	$max = 1 if (!@$recs);
	for (@$recs) {
		$max = $$_[1] if ($$_[1] > $max);
	}

	my $count = scalar(@$recs);
	for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
		next unless ($$rec[0]);
		my ($mrid,$rank,$skip) = @$rec;
		$client->respond( [$mrid, sprintf('%0.3f',$rank/$max), $skip, $count] );
	}
	return undef;
}

__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.post_filter.multiclass.search_fts.metarecord",
	method		=> 'postfilter_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.post_filter.multiclass.search_fts.metarecord.staff",
	method		=> 'postfilter_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.multiclass.search_fts",
	method		=> 'postfilter_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.multiclass.search_fts.staff",
	method		=> 'postfilter_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub biblio_search_multi_class_fts {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $sort = $args{'sort'};
	my $sort_dir = $args{sort_dir} || 'DESC';
	my $ou = $args{org_unit};
	my $ou_type = $args{depth};
	my $limit = $args{limit} || 10;
	my $visiblity_limit = $args{visiblity_limit} || 5000;
	my $offset = $args{offset} || 0;

	if (!$ou) {
		$ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
	}

	if (!defined($args{org_unit})) {
		die "No target organizational unit passed to ".$self->api_name;
	}

	if (! scalar( keys %{$args{searches}} )) {
		die "No search arguments were passed to ".$self->api_name;
	}

	my $outer_limit = 1000;

	my $limit_clause = '';
	my $offset_clause = '';

	$limit_clause = "LIMIT $outer_limit";
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

	my (@types,@forms,@lang,@aud,@lit_form);
	my ($t_filter, $f_filter) = ('','');
	my ($a_filter, $l_filter, $lf_filter) = ('','','');
	my ($ot_filter, $of_filter) = ('','');
	my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		@aud = @$a;
			
		$a_filter = ' AND rd.audience IN ('.join(',',map{'?'}@aud).')';
		$oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		@lang = @$l;

		$l_filter = ' AND rd.item_lang IN ('.join(',',map{'?'}@lang).')';
		$ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		@lit_form = @$f;

		$lf_filter = ' AND rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
		$olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
	}

	if (my $f = $args{item_form}) {
		$f = [$f] if (!ref($f));
		@forms = @$f;

		$f_filter = ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		$of_filter = ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
	}

	if (my $t = $args{item_type}) {
		$t = [$t] if (!ref($t));
		@types = @$t;

		$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
	}


	# XXX legacy format and item type support
	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
			$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
			$of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}


	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

	my $search_table_list = '';
	my $fts_list = '';
	my $join_table_list = '';
	my @rank_list;


	my @bonus_lists;
	my @bonus_values;
	my $prev_search_class;
	my $curr_search_class;
	for my $search_class (sort keys %{$args{searches}}) {
		$prev_search_class = $curr_search_class if ($curr_search_class);

		$curr_search_class = $search_class;

		my $class = $_cdbi->{$search_class};
		my $search_table = $class->table;

		my ($index_col) = $class->columns('FTS');
		$index_col ||= 'value';

		
		my $fts = OpenILS::Application::Storage::FTS->compile($args{searches}{$search_class}{term}, $search_class.'.value', "$search_class.$index_col");

		my $fts_where = $fts->sql_where_clause;
		my @fts_ranks = $fts->fts_rank;

		my $SQLstring = join('%',map { lc($_) } $fts->words);
		my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
		my $first_word = lc(($fts->words)[0]).'%';

		my $rank = join(' + ', @fts_ranks);

		my %bonus = ();
		$bonus{'keyword'} = [ { "CASE WHEN $search_class.value ILIKE ? THEN 1.2 ELSE 1 END" => $SQLstring } ];

		$bonus{'series'} = [
			{ "CASE WHEN $search_class.value ILIKE ? THEN 1.5 ELSE 1 END" => $first_word },
			{ "CASE WHEN $search_class.value ~ ? THEN 200 ELSE 1 END" => $REstring },
		];

		$bonus{'title'} = [ @{ $bonus{'series'} }, @{ $bonus{'keyword'} } ];

		my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$search_class} };
		$bonus_list ||= '1';

		push @bonus_lists, $bonus_list;
		push @bonus_values, map { values %$_ } @{ $bonus{$search_class} };

		#---------------------

		$search_table_list .= "$search_table $search_class, ";
		push @rank_list,$rank;
		$fts_list .= " AND $fts_where AND b.id = $search_class.source";

		if ($prev_search_class) {
			$join_table_list .= " AND $prev_search_class.source = $curr_search_class.source";
		}
	}

	my $metabib_record_descriptor = metabib::record_descriptor->table;
	my $metabib_full_rec = metabib::full_rec->table;
	my $metabib_metarecord = metabib::metarecord->table;
	my $metabib_metarecord_source_map_table = metabib::metarecord_source_map->table;
	my $asset_call_number_table = asset::call_number->table;
	my $asset_copy_table = asset::copy->table;
	my $cs_table = config::copy_status->table;
	my $cl_table = asset::copy_location->table;
	my $br_table = biblio::record_entry->table;
	my $source_table = config::bib_source->table;


	my $bonuses = join (' * ', @bonus_lists);
	my $relevance = join (' + ', @rank_list);
	$relevance = "AVG( ($relevance) * ($bonuses) )";


	my $rank = $relevance;
	if (lc($sort) eq 'pubdate') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(frp.value FROM '\\\\d{4}'),'9999')::INT
				  FROM	$metabib_full_rec frp
				  WHERE	frp.record = b.id
				  	AND frp.tag = '260'
					AND frp.subfield = 'c'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'create_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT create_date FROM $br_table rbr WHERE rbr.id = b.id)) )
		RANK
	} elsif (lc($sort) eq 'edit_date') {
		$rank = <<"		RANK";
			( FIRST (( SELECT edit_date FROM $br_table rbr WHERE rbr.id = b.id)) )
		RANK
	} elsif (lc($sort) eq 'title') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM '\\\\d+'),'0')::INT )),'zzzzzzzz')
				  FROM	$metabib_full_rec frt
				  WHERE	frt.record = b.id
				  	AND frt.tag = '245'
					AND frt.subfield = 'a'
				  LIMIT 1
			)) )
		RANK
	} elsif (lc($sort) eq 'author') {
		$rank = <<"		RANK";
			( FIRST((
				SELECT	COALESCE(LTRIM(fra.value),'zzzzzzzz')
				  FROM	$metabib_full_rec fra
				  WHERE	fra.record = b.id
				  	AND fra.tag LIKE '1%'
					AND fra.subfield = 'a'
				  ORDER BY fra.tag::text::int
				  LIMIT 1
			)) )
		RANK
	} else {
		push @bonus_values, @bonus_values;
		$sort = undef;
	}


	my $select = <<"	SQL";
		SELECT	b.id,
			$relevance AS rel,
			$rank AS rank,
			src.transcendant
  	  	FROM	$search_table_list
			$metabib_record_descriptor rd,
			$source_table src,
			$br_table b
	  	WHERE	rd.record = b.id
			AND src.id = b.source
			AND b.active IS TRUE
			AND b.deleted IS FALSE
			$fts_list
			$join_table_list
			$t_filter
			$f_filter
			$a_filter
			$l_filter
			$lf_filter
  	  	GROUP BY b.id, src.transcendant
  	  	ORDER BY 3 $sort_dir
		LIMIT $visiblity_limit
	SQL

	if ($self->api_name !~ /staff/o) {
		$select = <<"		SQL";

			SELECT	s.*
			  FROM	($select) s
			  WHERE	EXISTS (
			  	SELECT	1
				  FROM	$asset_call_number_table cn,
					$asset_copy_table cp,
					$cs_table cs,
					$cl_table cl,
					$descendants d
				  WHERE	cn.record = s.id
					AND cp.status = cs.id
					AND cp.location = cl.id
					AND cn.owning_lib = d.id
					AND cp.call_number = cn.id
					AND cp.opac_visible IS TRUE
					AND cs.holdable IS TRUE
					AND cl.opac_visible IS TRUE
					AND cp.deleted IS FALSE
					AND cn.deleted IS FALSE
				  LIMIT 1
			  	)
				OR transcendant IS TRUE
			  ORDER BY 3 $sort_dir
		SQL
	} else {
		$select = <<"		SQL";

			SELECT	s.*
			  FROM	($select) s
			  WHERE	EXISTS (
			  	SELECT	1
				  FROM	$asset_call_number_table cn,
					$descendants d
				  WHERE	cn.record = s.id
					AND cn.owning_lib = d.id
					AND cn.deleted IS FALSE
				  LIMIT 1
				)
				OR NOT EXISTS (
				SELECT	1
				  FROM	$asset_call_number_table cn
				  WHERE	cn.record = s.id
				  LIMIT 1
				)
				OR transcendant IS TRUE
			  ORDER BY 3 $sort_dir
		SQL
	}


	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $recs = $_cdbi->{title}->db_Main->selectall_arrayref(
			$select, {},
			@bonus_values, @types, @forms, @aud, @lang, @lit_form
	);
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	my $max = 0;
	$max = 1 if (!@$recs);
	for (@$recs) {
		$max = $$_[1] if ($$_[1] > $max);
	}

	my $count = scalar(@$recs);
	for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
		next unless ($$rec[0]);
		my ($mrid,$rank) = @$rec;
		$client->respond( [$mrid, sprintf('%0.3f',$rank/$max), $count] );
	}
	return undef;
}

__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.search_fts.record",
	method		=> 'biblio_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.search_fts.record.staff",
	method		=> 'biblio_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);



__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.search_fts",
	method		=> 'biblio_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.search_fts.staff",
	method		=> 'biblio_search_multi_class_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);


1;

