package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage::Publisher/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::JSON;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;

use OpenILS::Application::Storage::QueryParser;

my $log = 'OpenSRF::Utils::Logger';

$VERSION = 1;

sub _initialize_parser {
    my ($parser) = @_;

    my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );
    $parser->initialize(
        config_record_attr_index_norm_map =>
            $cstore->request(
                'open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic',
                { id => { "!=" => undef } },
                { flesh => 1, flesh_fields => { crainm => [qw/norm/] }, order_by => [{ class => "crainm", field => "pos" }] }
            )->gather(1),
        search_relevance_adjustment         =>
            $cstore->request(
                'open-ils.cstore.direct.search.relevance_adjustment.search.atomic',
                { id => { "!=" => undef } }
            )->gather(1),
        config_metabib_field                =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_field.search.atomic',
                { id => { "!=" => undef } }
            )->gather(1),
        config_metabib_search_alias         =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_search_alias.search.atomic',
                { alias => { "!=" => undef } }
            )->gather(1),
        config_metabib_field_index_norm_map =>
            $cstore->request(
                'open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic',
                { id => { "!=" => undef } },
                { flesh => 1, flesh_fields => { cmfinm => [qw/norm/] }, order_by => [{ class => "cmfinm", field => "pos" }] }
            )->gather(1),
        config_record_attr_definition       =>
            $cstore->request(
                'open-ils.cstore.direct.config.record_attr_definition.search.atomic',
                { name => { "!=" => undef } }
            )->gather(1),
    );

    $cstore->disconnect;
    die("Cannot initialize $parser!") unless ($parser->initialization_complete);
}

sub ordered_records_from_metarecord {
	my $self = shift;
	my $client = shift;
	my $mr = shift;
	my $formats = shift;
	my $org = shift || 1;
	my $depth = shift;

	my (@types,@forms,@blvl);

	if ($formats) {
		my ($t, $f, $b) = split '-', $formats;
		@types = split '', $t;
		@forms = split '', $f;
		@blvl = split '', $b;
	}

	my $descendants =
		defined($depth) ?
			"actor.org_unit_descendants($org, $depth)" :
			"actor.org_unit_descendants($org)" ;


	my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';
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
			FIRST(COALESCE(LTRIM(SUBSTR( value, COALESCE(SUBSTRING(ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'zzzzzzzz')) AS title
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

	if (@blvl) {
		$sql .= '				AND rd.bib_level IN ('.join(',',map{'?'}@blvl).')';
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

	my $ids = metabib::metarecord_source_map->db_Main->selectcol_arrayref($sql, {}, "$mr", @types, @forms, @blvl);
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

# XXX: this subroutine and its two registered methods are marked for 
# deprecation, as they do not work properly in 2.x (these tags are no longer
# normalized in mfr) and are not in known use
sub isxn_search {
	my $self = shift;
	my $client = shift;
	my $isxn = lc(shift());

	$isxn =~ s/^\s*//o;
	$isxn =~ s/\s*$//o;
	$isxn =~ s/-//o if ($self->api_name =~ /isbn/o);

	my $tag = ($self->api_name =~ /isbn/o) ? "'020' OR f.tag = '024'" : "'022'";

	my $fr_table = metabib::full_rec->table;
	my $bib_table = biblio::record_entry->table;

	my $sql = <<"	SQL";
		SELECT	DISTINCT f.record
		  FROM	$fr_table f
			JOIN $bib_table b ON (b.id = f.record)
		  WHERE	(f.tag = $tag)
			AND f.value LIKE ?
			AND b.deleted IS FALSE
	SQL

	my $list = metabib::full_rec->db_Main->selectcol_arrayref($sql, {}, "$isxn%");
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
	my $br_table = biblio::record_entry->table;
	my $src_table = config::bib_source->table;
	my $cl_table = asset::copy_location->table;
	my $cs_table = config::copy_status->table;
	my $out_table = actor::org_unit_type->table;

	my $descendants = "actor.org_unit_descendants(u.id)";
	my $ancestors = "actor.org_unit_ancestors(?) u JOIN $out_table t ON (u.ou_type = t.id)";

    if ($args{org_unit} < 0) {
        $args{org_unit} *= -1;
        $ancestors = "(select org_unit as id from actor.org_lasso_map where lasso = ?) u CROSS JOIN (SELECT -1 AS depth) t";
    }

	my $copies_visible = 'AND a.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my (@types,@forms,@blvl);
	my ($t_filter, $f_filter, $b_filter) = ('','','');

	if ($args{format}) {
		my ($t, $f, $b) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		@blvl = split '', $b;

		if (@types) {
			$t_filter = ' AND rd.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter .= ' AND rd.item_form IN ('.join(',',map{'?'}@forms).')';
		}

		if (@blvl) {
			$b_filter .= ' AND rd.bib_level IN ('.join(',',map{'?'}@blvl).')';
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
					$b_filter
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
				  	AND cp.status IN (0,7,12)
				  	AND cn.deleted IS FALSE
				  	AND cp.deleted IS FALSE
					$copies_visible
					$t_filter
					$f_filter
					$b_filter
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
					AND cs.opac_visible IS TRUE
					AND cl.opac_visible IS TRUE
					$t_filter
					$f_filter
					$b_filter
				)
			) AS unshadow,
			sum(	
				(SELECT sum(1)
				  FROM  $sm_table r
			       		JOIN $br_table br ON (br.id = r.source)
			       		JOIN $src_table src ON (src.id = br.source)
				  WHERE r.metarecord = ?
				  	AND src.transcendant IS TRUE
				)
			) AS transcendant

		  FROM  $ancestors
		  GROUP BY 1,2
	SQL

	my $sth = metabib::metarecord_source_map->db_Main->prepare_cached($sql);
	$sth->execute(	''.$args{metarecord},
			@types, 
			@forms,
			@blvl,
			''.$args{metarecord},
			@types, 
			@forms,
			@blvl,
			''.$args{metarecord},
			@types, 
			@forms,
			@blvl,
			''.$args{metarecord},
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
    my $self   = shift;
    my $client = shift;
    my %args   = @_;

    my $class_join = $args{class_join} || 'AND';
    my $limit      = $args{limit}      || 100;
    my $offset     = $args{offset}     || 0;
    my $sort       = $args{'sort'};
    my $sort_dir   = $args{sort_dir}   || 'DESC';

	my @binds;
	my @selects;

	for my $arg (@{ $args{searches} }) {
		my $term     = $$arg{term};
		my $limiters = $$arg{restrict};

		my ($index_col)  = metabib::full_rec->columns('FTS');
		$index_col ||= 'value';
		my $search_table = metabib::full_rec->table;

		my $fts = OpenILS::Application::Storage::FTS->compile('default' => $term, 'value',"$index_col");

		my $fts_where = $fts->sql_where_clause();
		my @fts_ranks = $fts->fts_rank;

		my $rank = join(' + ', @fts_ranks);

		my @wheres;
		for my $limit (@$limiters) {
			if ($$limit{tag} =~ /^\d+$/ and $$limit{tag} < 10) {
				# MARC control field; mfr.subfield is NULL
				push @wheres, "( tag = ? AND $fts_where )";
				push @binds, $$limit{tag};
 				$log->debug("Limiting query using { tag => $$limit{tag} }", DEBUG);
			} else {
				push @wheres, "( tag = ? AND subfield LIKE ? AND $fts_where )";
				push @binds, $$limit{tag}, $$limit{subfield};
 				$log->debug("Limiting query using { tag => $$limit{tag}, subfield => $$limit{subfield} }", DEBUG);
			}
		}
		my $where = join(' OR ', @wheres);

		push @selects, "SELECT record, AVG($rank) as sum FROM $search_table WHERE $where GROUP BY record";

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

	my $cj = 'HAVING COUNT(x.record) = ' . scalar(@selects) if ($class_join eq 'AND');
	my $search_table =
		'(SELECT x.record, sum(x.sum) FROM (('.
			join(') UNION ALL (', @selects).
			")) x GROUP BY 1 $cj ORDER BY 2 DESC )";

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';

	if ($self->api_name =~ /staff/o) {
		$copies_visible = '';
		$has_copies     = '' if ($ou_type == 0);
		$has_vols       = '' if ($ou_type == 0);
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
				SELECT	COALESCE(SUBSTRING(frp.value FROM E'\\\\d+'),'9999')::INT
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
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'zzzzzzzz')
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

	my $fts = OpenILS::Application::Storage::FTS->compile('default' => $term, 'value',"$index_col");

	my $fts_where = $fts->sql_where_clause();
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my @binds;
	my @wheres;
	for my $limit (@$limiters) {
		if ($$limit{tag} =~ /^\d+$/ and $$limit{tag} < 10) {
			# MARC control field; mfr.subfield is NULL
			push @wheres, "( tag = ? AND $fts_where )";
			push @binds, $$limit{tag};
 			$log->debug("Limiting query using { tag => $$limit{tag} }", DEBUG);
		} else {
			push @wheres, "( tag = ? AND subfield LIKE ? AND $fts_where )";
			push @binds, $$limit{tag}, $$limit{subfield};
 			$log->debug("Limiting query using { tag => $$limit{tag}, subfield => $$limit{subfield} }", DEBUG);
		}
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

	(my $search_class = $self->api_name) =~ s/.*metabib.(\w+).search_fts.*/$1/o;
	my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $term, 'f.value', "f.$index_col");

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my $rank = join(' + ', @fts_ranks);

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';

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

for my $class ( qw/title author subject keyword series identifier/ ) {
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

	my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $term, 'value',"$index_col");

	my $fts_where = $fts->sql_where_clause;

	my $has_vols = 'AND cn.owning_lib = d.id';
	my $has_copies = 'AND cp.call_number = cn.id';
	my $copies_visible = 'AND d.opac_visible IS TRUE AND cp.opac_visible IS TRUE AND cs.opac_visible IS TRUE AND cl.opac_visible IS TRUE';
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
for my $class ( qw/title author subject keyword series identifier/ ) {
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
	my $visibility_limit = $args{visibility_limit} || 5000;
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

	(my $search_class = $self->api_name) =~ s/.*metabib.(\w+).post_filter.*/$1/o;

	my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $term, 'f.value', "f.$index_col");

	my $SQLstring = join('%',map { lc($_) } $fts->words);
	my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
	my $first_word = lc(($fts->words)[0]).'%';

	my $fts_where = $fts->sql_where_clause;
	my @fts_ranks = $fts->fts_rank;

	my %bonus = ();
	$bonus{'metabib::identifier_field_entry'} =
        $bonus{'metabib::keyword_field_entry'} = [
            { 'CASE WHEN f.value ILIKE ? THEN 1.2 ELSE 1 END' => $SQLstring }
        ];

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

	my $string_default_sort = 'zzzz';
	$string_default_sort = 'AAAA' if ($sort_dir eq 'DESC');

	my $number_default_sort = '9999';
	$number_default_sort = '0000' if ($sort_dir eq 'DESC');

	my $rank = $relevance;
	if (lc($sort) eq 'pubdate') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(frp.value FROM E'\\\\d+'),'$number_default_sort')::INT
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
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
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
				SELECT	COALESCE(LTRIM(fra.value),'$string_default_sort')
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
		LIMIT $visibility_limit
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
				AND cs.opac_visible IS TRUE
				AND cl.opac_visible IS TRUE
				AND d.opac_visible IS TRUE
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
					AND cp.circ_lib = d.id
					AND cp.call_number = cn.id
					AND cp.opac_visible IS TRUE
					AND cs.opac_visible IS TRUE
					AND cl.opac_visible IS TRUE
					AND d.opac_visible IS TRUE
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
					$asset_copy_table cp,
					$metabib_metarecord_source_map_table mrs,
					$br_table br,
					$descendants d,
					$metabib_record_descriptor ord
				
				  WHERE	mrs.metarecord = s.metarecord
					AND br.id = mrs.source
					AND cn.record = mrs.source
					AND cn.id = cp.call_number
					AND br.deleted IS FALSE
					AND cn.deleted IS FALSE
					AND ord.record = mrs.source
					AND (	cn.owning_lib = d.id
						OR (	cp.circ_lib = d.id
							AND cp.deleted IS FALSE
						)
					)
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

for my $class ( qw/title author subject keyword series identifier/ ) {
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
		identifier	=> "metabib::identifier_field_entry",
};

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub postfilter_search_multi_class_fts {
    my $self   = shift;
    my $client = shift;
    my %args   = @_;
	
    my $sort             = $args{'sort'};
    my $sort_dir         = $args{sort_dir} || 'DESC';
    my $ou               = $args{org_unit};
    my $ou_type          = $args{depth};
    my $limit            = $args{limit}  || 10;
    my $offset           = $args{offset} ||  0;
    my $visibility_limit = $args{visibility_limit} || 5000;

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

	my $limit_clause  = '';
	my $offset_clause = '';

	$limit_clause  = "LIMIT $outer_limit";
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

	my ($avail_filter,@types,@forms,@lang,@aud,@lit_form,@vformats) = ('');
	my ($t_filter,   $f_filter,   $v_filter) = ('','','');
	my ($a_filter,   $l_filter,  $lf_filter) = ('','','');
	my ($ot_filter, $of_filter,  $ov_filter) = ('','','');
	my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

	if ($args{available}) {
		$avail_filter = ' AND cp.status IN (0,7,12)';
	}

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		@aud = @$a;
			
		$a_filter  = ' AND  rd.audience IN ('.join(',',map{'?'}@aud).')';
		$oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		@lang = @$l;

		$l_filter  = ' AND  rd.item_lang IN ('.join(',',map{'?'}@lang).')';
		$ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		@lit_form = @$f;

		$lf_filter  = ' AND  rd.lit_form IN ('.join(',',map{'?'}@lit_form).')';
		$olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
	}

	if (my $f = $args{item_form}) {
		$f = [$f] if (!ref($f));
		@forms = @$f;

		$f_filter  = ' AND  rd.item_form IN ('.join(',',map{'?'}@forms).')';
		$of_filter = ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
	}

	if (my $t = $args{item_type}) {
		$t = [$t] if (!ref($t));
		@types = @$t;

		$t_filter  = ' AND  rd.item_type IN ('.join(',',map{'?'}@types).')';
		$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
	}

	if (my $v = $args{vr_format}) {
		$v = [$v] if (!ref($v));
		@vformats = @$v;

		$v_filter  = ' AND  rd.vr_format IN ('.join(',',map{'?'}@vformats).')';
		$ov_filter = ' AND ord.vr_format IN ('.join(',',map{'?'}@vformats).')';
	}


	# XXX legacy format and item type support
	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter  = ' AND  rd.item_type IN ('.join(',',map{'?'}@types).')';
			$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter  .= ' AND  rd.item_form IN ('.join(',',map{'?'}@forms).')';
			$of_filter .= ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
		}
	}



	my $descendants = defined($ou_type) ?
				"actor.org_unit_descendants($ou, $ou_type)" :
				"actor.org_unit_descendants($ou)";

    my $search_table_list = '';
    my $fts_list          = '';
    my $join_table_list   = '';
    my @rank_list;

	my $field_table = config::metabib_field->table;

	my @bonus_lists;
	my @bonus_values;
	my $prev_search_group;
	my $curr_search_group;
	my $search_class;
	my $search_field;
	my $metabib_field;
	for my $search_group (sort keys %{$args{searches}}) {
		(my $search_group_name = $search_group) =~ s/\|/_/gso;
		($search_class,$search_field) = split /\|/, $search_group;
		$log->debug("Searching class [$search_class] and field [$search_field]",DEBUG);

		if ($search_field) {
			unless ( $metabib_field = config::metabib_field->search( field_class => $search_class, name => $search_field )->next ) {
				$log->warn("Requested class [$search_class] or field [$search_field] does not exist!");
				return undef;
			}
		}

		$prev_search_group = $curr_search_group if ($curr_search_group);

		$curr_search_group = $search_group_name;

		my $class = $_cdbi->{$search_class};
		my $search_table = $class->table;

		my ($index_col) = $class->columns('FTS');
		$index_col ||= 'value';

		
		my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $args{searches}{$search_group}{term}, $search_group_name.'.value', "$search_group_name.$index_col");

		my $fts_where = $fts->sql_where_clause;
		my @fts_ranks = $fts->fts_rank;

		my $SQLstring = join('%',map { lc($_) } $fts->words);
		my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
		my $first_word = lc(($fts->words)[0]).'%';

		$_.=" * (SELECT weight FROM $field_table WHERE $search_group_name.field = id)" for (@fts_ranks);
		my $rank = join(' + ', @fts_ranks);

		my %bonus = ();
		$bonus{'keyword'} = [ { "CASE WHEN $search_group_name.value LIKE ? THEN 10 ELSE 1 END" => $SQLstring } ];
		$bonus{'author'}  = [ { "CASE WHEN $search_group_name.value ILIKE ? THEN 10 ELSE 1 END" => $first_word } ];

		$bonus{'series'} = [
			{ "CASE WHEN $search_group_name.value LIKE ? THEN 1.5 ELSE 1 END" => $first_word },
			{ "CASE WHEN $search_group_name.value ~ ? THEN 20 ELSE 1 END" => $REstring },
		];

		$bonus{'title'} = [ @{ $bonus{'series'} }, @{ $bonus{'keyword'} } ];

		my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$search_class} };
		$bonus_list ||= '1';

		push @bonus_lists, $bonus_list;
		push @bonus_values, map { values %$_ } @{ $bonus{$search_class} };


		#---------------------

		$search_table_list .= "$search_table $search_group_name, ";
		push @rank_list,$rank;
		$fts_list .= " AND $fts_where AND m.source = $search_group_name.source";

		if ($metabib_field) {
			$join_table_list .= " AND $search_group_name.field = " . $metabib_field->id;
			$metabib_field = undef;
		}

		if ($prev_search_group) {
			$join_table_list .= " AND $prev_search_group.source = $curr_search_group.source";
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

	my $string_default_sort = 'zzzz';
	$string_default_sort = 'AAAA' if ($sort_dir eq 'DESC');

	my $number_default_sort = '9999';
	$number_default_sort = '0000' if ($sort_dir eq 'DESC');



	my $secondary_sort = <<"	SORT";
		( FIRST ((
			SELECT	COALESCE(LTRIM(SUBSTR( sfrt.value, COALESCE(SUBSTRING(sfrt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
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
				SELECT	COALESCE(SUBSTRING(frp.value FROM E'\\\\d+'),'$number_default_sort')::INT
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
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
				  FROM	$metabib_full_rec frt
				  WHERE	frt.record = mr.master_record
				  	AND frt.tag = '245'
					AND frt.subfield = 'a'
				  LIMIT 1
			)) )
		RANK
		$secondary_sort = <<"		SORT";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(sfrp.value FROM E'\\\\d+'),'$number_default_sort')::INT
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
				SELECT	COALESCE(LTRIM(fra.value),'$string_default_sort')
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
		LIMIT $visibility_limit
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
					AND cp.circ_lib = d.id
					AND cp.call_number = cn.id
					AND cp.opac_visible IS TRUE
					AND cs.opac_visible IS TRUE
					AND cl.opac_visible IS TRUE
					AND d.opac_visible IS TRUE
					AND br.active IS TRUE
					AND br.deleted IS FALSE
					AND cp.deleted IS FALSE
					AND cn.deleted IS FALSE
					AND ord.record = mrs.source
					$ot_filter
					$of_filter
					$ov_filter
					$oa_filter
					$ol_filter
					$olf_filter
					$avail_filter
				  LIMIT 1
			  	)
				OR EXISTS (
				SELECT	1
				  FROM	$br_table br,
					$metabib_metarecord_source_map_table mrs,
					$metabib_record_descriptor ord,
					$source_table src
				  WHERE	mrs.metarecord = s.metarecord
					AND ord.record = mrs.source
					AND br.id = mrs.source
					AND br.source = src.id
					AND src.transcendant IS TRUE
					$ot_filter
					$of_filter
					$ov_filter
					$oa_filter
					$ol_filter
					$olf_filter
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
							$asset_copy_table cp,
							$descendants d,
							$br_table br
						  WHERE	br.id = omrs.source
							AND cn.record = omrs.source
							AND br.deleted IS FALSE
							AND cn.deleted IS FALSE
							AND cp.call_number = cn.id
							AND (	cn.owning_lib = d.id
								OR (	cp.circ_lib = d.id
									AND cp.deleted IS FALSE
								)
							)
							$avail_filter
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
						$metabib_record_descriptor ord,
						$source_table src
					  WHERE	mrs.metarecord = s.metarecord
						AND br.id = mrs.source
						AND br.source = src.id
						AND src.transcendant IS TRUE
						$ot_filter
						$of_filter
						$ov_filter
						$oa_filter
						$ol_filter
						$olf_filter
					)
				)
				$ot_filter
				$of_filter
				$ov_filter
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
			@types, @forms, @vformats, @aud, @lang, @lit_form,
			@types, @forms, @vformats, @aud, @lang, @lit_form,
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
	
    my $sort             = $args{'sort'};
    my $sort_dir         = $args{sort_dir} || 'DESC';
    my $ou               = $args{org_unit};
    my $ou_type          = $args{depth};
    my $limit            = $args{limit}  || 10;
    my $offset           = $args{offset} ||  0;
    my $pref_lang        = $args{preferred_language} || 'eng';
    my $visibility_limit = $args{visibility_limit}  || 5000;

	if (!$ou) {
		$ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
	}

	if (! scalar( keys %{$args{searches}} )) {
		die "No search arguments were passed to ".$self->api_name;
	}

	my $outer_limit = 1000;

	my $limit_clause  = '';
	my $offset_clause = '';

	$limit_clause  = "LIMIT $outer_limit";
	$offset_clause = "OFFSET $offset" if (defined $offset and int($offset) > 0);

	my ($avail_filter,@types,@forms,@lang,@aud,@lit_form,@vformats) = ('');
	my ($t_filter,   $f_filter,   $v_filter) = ('','','');
	my ($a_filter,   $l_filter,  $lf_filter) = ('','','');
	my ($ot_filter, $of_filter,  $ov_filter) = ('','','');
	my ($oa_filter, $ol_filter, $olf_filter) = ('','','');

	if ($args{available}) {
		$avail_filter = ' AND cp.status IN (0,7,12)';
	}

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		@aud = @$a;
			
		$a_filter  = ' AND rd.audience  IN ('.join(',',map{'?'}@aud).')';
		$oa_filter = ' AND ord.audience IN ('.join(',',map{'?'}@aud).')';
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		@lang = @$l;

		$l_filter  = ' AND rd.item_lang  IN ('.join(',',map{'?'}@lang).')';
		$ol_filter = ' AND ord.item_lang IN ('.join(',',map{'?'}@lang).')';
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		@lit_form = @$f;

		$lf_filter  = ' AND rd.lit_form  IN ('.join(',',map{'?'}@lit_form).')';
		$olf_filter = ' AND ord.lit_form IN ('.join(',',map{'?'}@lit_form).')';
	}

	if (my $f = $args{item_form}) {
		$f = [$f] if (!ref($f));
		@forms = @$f;

		$f_filter  = ' AND rd.item_form  IN ('.join(',',map{'?'}@forms).')';
		$of_filter = ' AND ord.item_form IN ('.join(',',map{'?'}@forms).')';
	}

	if (my $t = $args{item_type}) {
		$t = [$t] if (!ref($t));
		@types = @$t;

		$t_filter  = ' AND rd.item_type  IN ('.join(',',map{'?'}@types).')';
		$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
	}

	if (my $v = $args{vr_format}) {
		$v = [$v] if (!ref($v));
		@vformats = @$v;

		$v_filter  = ' AND rd.vr_format  IN ('.join(',',map{'?'}@vformats).')';
		$ov_filter = ' AND ord.vr_format IN ('.join(',',map{'?'}@vformats).')';
	}

	# XXX legacy format and item type support
	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
		if (@types) {
			$t_filter  = ' AND rd.item_type  IN ('.join(',',map{'?'}@types).')';
			$ot_filter = ' AND ord.item_type IN ('.join(',',map{'?'}@types).')';
		}

		if (@forms) {
			$f_filter  .= ' AND rd.item_form  IN ('.join(',',map{'?'}@forms).')';
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

	my $field_table = config::metabib_field->table;

	my @bonus_lists;
	my @bonus_values;
	my $prev_search_group;
	my $curr_search_group;
	my $search_class;
	my $search_field;
	my $metabib_field;
	for my $search_group (sort keys %{$args{searches}}) {
		(my $search_group_name = $search_group) =~ s/\|/_/gso;
		($search_class,$search_field) = split /\|/, $search_group;
		$log->debug("Searching class [$search_class] and field [$search_field]",DEBUG);

		if ($search_field) {
			unless ( $metabib_field = config::metabib_field->search( field_class => $search_class, name => $search_field )->next ) {
				$log->warn("Requested class [$search_class] or field [$search_field] does not exist!");
				return undef;
			}
		}

		$prev_search_group = $curr_search_group if ($curr_search_group);

		$curr_search_group = $search_group_name;

		my $class = $_cdbi->{$search_class};
		my $search_table = $class->table;

		my ($index_col) = $class->columns('FTS');
		$index_col ||= 'value';

		
		my $fts = OpenILS::Application::Storage::FTS->compile($search_class => $args{searches}{$search_group}{term}, $search_group_name.'.value', "$search_group_name.$index_col");

		my $fts_where = $fts->sql_where_clause;
		my @fts_ranks = $fts->fts_rank;

		my $SQLstring = join('%',map { lc($_) } $fts->words) .'%';
		my $REstring = '^' . join('\s+',map { lc($_) } $fts->words) . '\W*$';
		my $first_word = lc(($fts->words)[0]).'%';

		$_.=" * (SELECT weight FROM $field_table WHERE $search_group_name.field = id)" for (@fts_ranks);
		my $rank = join('  + ', @fts_ranks);

		my %bonus = ();
		$bonus{'subject'} = [];
		$bonus{'author'}  = [ { "CASE WHEN $search_group_name.value ILIKE ? THEN 1.5 ELSE 1 END" => $first_word } ];

		$bonus{'keyword'} = [ { "CASE WHEN $search_group_name.value ILIKE ? THEN 10 ELSE 1 END" => $SQLstring } ];

		$bonus{'series'} = [
			{ "CASE WHEN $search_group_name.value ILIKE ? THEN 1.5 ELSE 1 END" => $first_word },
			{ "CASE WHEN $search_group_name.value ~ ? THEN 20 ELSE 1 END" => $REstring },
		];

		$bonus{'title'} = [ @{ $bonus{'series'} }, @{ $bonus{'keyword'} } ];

		if ($pref_lang) {
			push @{ $bonus{'title'}   }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
			push @{ $bonus{'author'}  }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
			push @{ $bonus{'subject'} }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
			push @{ $bonus{'keyword'} }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
			push @{ $bonus{'series'}  }, { "CASE WHEN rd.item_lang = ? THEN 10 ELSE 1 END" => $pref_lang };
		}

		my $bonus_list = join ' * ', map { keys %$_ } @{ $bonus{$search_class} };
		$bonus_list ||= '1';

		push @bonus_lists, $bonus_list;
		push @bonus_values, map { values %$_ } @{ $bonus{$search_class} };

		#---------------------

		$search_table_list .= "$search_table $search_group_name, ";
		push @rank_list,$rank;
		$fts_list .= " AND $fts_where AND b.id = $search_group_name.source";

		if ($metabib_field) {
			$fts_list .= " AND $curr_search_group.field = " . $metabib_field->id;
			$metabib_field = undef;
		}

		if ($prev_search_group) {
			$join_table_list .= " AND $prev_search_group.source = $curr_search_group.source";
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

	my $string_default_sort = 'zzzz';
	$string_default_sort = 'AAAA' if ($sort_dir eq 'DESC');

	my $number_default_sort = '9999';
	$number_default_sort = '0000' if ($sort_dir eq 'DESC');

	my $rank = $relevance;
	if (lc($sort) eq 'pubdate') {
		$rank = <<"		RANK";
			( FIRST ((
				SELECT	COALESCE(SUBSTRING(frp.value FROM E'\\\\d{4}'),'$number_default_sort')::INT
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
				SELECT	COALESCE(LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 )),'$string_default_sort')
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
				SELECT	COALESCE(LTRIM(fra.value),'$string_default_sort')
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
			b.source
  	  	FROM	$search_table_list
			$metabib_record_descriptor rd,
			$source_table src,
			$br_table b
	  	WHERE	rd.record = b.id
			AND b.active IS TRUE
			AND b.deleted IS FALSE
			$fts_list
			$join_table_list
			$t_filter
			$f_filter
			$v_filter
			$a_filter
			$l_filter
			$lf_filter
  	  	GROUP BY b.id, b.source
  	  	ORDER BY 3 $sort_dir
		LIMIT $visibility_limit
	SQL

	if ($self->api_name !~ /staff/o) {
		$select = <<"		SQL";

			SELECT	s.*
			  FROM	($select) s
			  	LEFT OUTER JOIN $source_table src ON (s.source = src.id)
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
					AND cp.call_number = cn.id
					AND cp.opac_visible IS TRUE
					AND cs.opac_visible IS TRUE
					AND cl.opac_visible IS TRUE
					AND d.opac_visible IS TRUE
					AND cp.deleted IS FALSE
					AND cn.deleted IS FALSE
					AND cp.circ_lib = d.id
					$avail_filter
				  LIMIT 1
			  	)
				OR src.transcendant IS TRUE
			  ORDER BY 3 $sort_dir
		SQL
	} else {
		$select = <<"		SQL";

			SELECT	s.*
			  FROM	($select) s
			  	LEFT OUTER JOIN $source_table src ON (s.source = src.id)
			  WHERE	EXISTS (
			  	SELECT	1
				  FROM	$asset_call_number_table cn,
					$asset_copy_table cp,
					$descendants d
				  WHERE	cn.record = s.id
					AND cp.call_number = cn.id
					AND cn.deleted IS FALSE
					AND cp.circ_lib = d.id
					AND cp.deleted IS FALSE
					$avail_filter
				  LIMIT 1
				)
				OR NOT EXISTS (
				SELECT	1
				  FROM	$asset_call_number_table cn
				  WHERE	cn.record = s.id
				  LIMIT 1
				)
				OR src.transcendant IS TRUE
			  ORDER BY 3 $sort_dir
		SQL
	}


	$log->debug("Field Search SQL :: [$select]",DEBUG);

	my $recs = $_cdbi->{title}->db_Main->selectall_arrayref(
			$select, {},
			@bonus_values, @types, @forms, @vformats, @aud, @lang, @lit_form
	);
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	my $count = scalar(@$recs);
	for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
		next unless ($$rec[0]);
		my ($mrid,$rank) = @$rec;
		$client->respond( [$mrid, sprintf('%0.3f',$rank), $count] );
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


my %locale_map;
my $default_preferred_language;
my $default_preferred_language_weight;

# XXX factored most of the PG dependant stuff out of here... need to find a way to do "dependants".
sub staged_fts {
    my $self   = shift;
    my $client = shift;
    my %args   = @_;

    if (!$locale_map{COMPLETE}) {

        my @locales = config::i18n_locale->search_where({ code => { '<>' => '' } });
        for my $locale ( @locales ) {
            $locale_map{lc($locale->code)} = $locale->marc_code;
        }
        $locale_map{COMPLETE} = 1;

    }

    my $config = OpenSRF::Utils::SettingsClient->new();

    if (!$default_preferred_language) {

        $default_preferred_language = $config->config_value(
                apps => 'open-ils.search' => app_settings => 'default_preferred_language'
        ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language'
        );

    }

    if (!$default_preferred_language_weight) {

        $default_preferred_language_weight = $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language_weight'
        ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language_weight'
        );
    }

    # inclusion, exclusion, delete_adjusted_inclusion, delete_adjusted_exclusion
    my $estimation_strategy = $args{estimation_strategy} || 'inclusion';

    my $ou     = $args{org_unit};
    my $limit  = $args{limit}  || 10;
    my $offset = $args{offset} ||  0;

	if (!$ou) {
		$ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
	}

	if (! scalar( keys %{$args{searches}} )) {
		die "No search arguments were passed to ".$self->api_name;
	}

	my (@between,@statuses,@locations,@types,@forms,@lang,@aud,@lit_form,@vformats,@bib_level);

    if (!defined($args{preferred_language})) {
		my $ses_locale = $client->session ? $client->session->session_locale : $default_preferred_language;
        $args{preferred_language} =
            $locale_map{ lc($ses_locale) } || 'eng';
    }

    if (!defined($args{preferred_language_weight})) {
        $args{preferred_language_weight} = $default_preferred_language_weight || 2;
    }

	if ($args{available}) {
		@statuses = (0,7,12);
	}

	if (my $s = $args{locations}) {
		$s = [$s] if (!ref($s));
		@locations = @$s;
	}

	if (my $b = $args{between}) {
		if (ref($b) && @$b == 2) {
		    @between = @$b;
        }
	}

	if (my $s = $args{statuses}) {
		$s = [$s] if (!ref($s));
		@statuses = @$s;
	}

	if (my $a = $args{audience}) {
		$a = [$a] if (!ref($a));
		@aud = @$a;
	}

	if (my $l = $args{language}) {
		$l = [$l] if (!ref($l));
		@lang = @$l;
	}

	if (my $f = $args{lit_form}) {
		$f = [$f] if (!ref($f));
		@lit_form = @$f;
	}

	if (my $f = $args{item_form}) {
		$f = [$f] if (!ref($f));
		@forms = @$f;
	}

	if (my $t = $args{item_type}) {
		$t = [$t] if (!ref($t));
		@types = @$t;
	}

	if (my $b = $args{bib_level}) {
		$b = [$b] if (!ref($b));
		@bib_level = @$b;
	}

	if (my $v = $args{vr_format}) {
		$v = [$v] if (!ref($v));
		@vformats = @$v;
	}

	# XXX legacy format and item type support
	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		@types = split '', $t;
		@forms = split '', $f;
	}

    my %stored_proc_search_args;
	for my $search_group (sort keys %{$args{searches}}) {
		(my $search_group_name = $search_group) =~ s/\|/_/gso;
		my ($search_class,$search_field) = split /\|/, $search_group;
		$log->debug("Searching class [$search_class] and field [$search_field]",DEBUG);

		if ($search_field) {
			unless ( config::metabib_field->search( field_class => $search_class, name => $search_field )->next ) {
				$log->warn("Requested class [$search_class] or field [$search_field] does not exist!");
				return undef;
			}
		}

		my $class = $_cdbi->{$search_class};
		my $search_table = $class->table;

		my ($index_col) = $class->columns('FTS');
		$index_col ||= 'value';

		
		my $fts = OpenILS::Application::Storage::FTS->compile(
            $search_class => $args{searches}{$search_group}{term},
            $search_group_name.'.value',
            "$search_group_name.$index_col"
        );
		$fts->sql_where_clause; # this builds the ranks for us

		my @fts_ranks   = $fts->fts_rank;
		my @fts_queries = $fts->fts_query;
		my @phrases = map { lc($_) } $fts->phrases;
		my @words   = map { lc($_) } $fts->words;

        $stored_proc_search_args{$search_group} = {
            fts_rank    => \@fts_ranks,
            fts_query   => \@fts_queries,
            phrase      => \@phrases,
            word        => \@words,
        };

	}

	my $param_search_ou = $ou;
	my $param_depth = $args{depth}; $param_depth = 'NULL' unless (defined($param_depth) and length($param_depth) > 0 );
	my $param_searches = OpenSRF::Utils::JSON->perl2JSON( \%stored_proc_search_args ); $param_searches =~ s/\$//go; $param_searches = '$$'.$param_searches.'$$';
	my $param_statuses  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @statuses ) . '}$$';
	my $param_locations = '$${' . join(',', map { s/\$//go; "\"$_\"" } @locations) . '}$$';
	my $param_audience  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @aud      ) . '}$$';
	my $param_language  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @lang     ) . '}$$';
	my $param_lit_form  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @lit_form ) . '}$$';
	my $param_types     = '$${' . join(',', map { s/\$//go; "\"$_\"" } @types    ) . '}$$';
	my $param_forms     = '$${' . join(',', map { s/\$//go; "\"$_\"" } @forms    ) . '}$$';
	my $param_vformats  = '$${' . join(',', map { s/\$//go; "\"$_\"" } @vformats ) . '}$$';
    my $param_bib_level = '$${' . join(',', map { s/\$//go; "\"$_\"" } @bib_level) . '}$$';
	my $param_before = $args{before}; $param_before = 'NULL' unless (defined($param_before) and length($param_before) > 0 );
	my $param_after  = $args{after} ; $param_after  = 'NULL' unless (defined($param_after ) and length($param_after ) > 0 );
	my $param_during = $args{during}; $param_during = 'NULL' unless (defined($param_during) and length($param_during) > 0 );
    my $param_between = '$${"' . join('","', map { int($_) } @between) . '"}$$';
	my $param_pref_lang = $args{preferred_language}; $param_pref_lang =~ s/\$//go; $param_pref_lang = '$$'.$param_pref_lang.'$$';
	my $param_pref_lang_multiplier = $args{preferred_language_weight}; $param_pref_lang_multiplier ||= 'NULL';
	my $param_sort = $args{'sort'}; $param_sort =~ s/\$//go; $param_sort = '$$'.$param_sort.'$$';
	my $param_sort_desc = defined($args{sort_dir}) && $args{sort_dir} =~ /^d/io ? "'t'" : "'f'";
	my $metarecord = $self->api_name =~ /metabib/o ? "'t'" : "'f'";
	my $staff = $self->api_name =~ /staff/o ? "'t'" : "'f'";
    my $param_rel_limit = $args{core_limit};  $param_rel_limit ||= 'NULL';
    my $param_chk_limit = $args{check_limit}; $param_chk_limit ||= 'NULL';
    my $param_skip_chk  = $args{skip_check};  $param_skip_chk  ||= 'NULL';

	my $sth = metabib::metarecord_source_map->db_Main->prepare(<<"    SQL");
        SELECT  *
          FROM  search.staged_fts(
                    $param_search_ou\:\:INT,
                    $param_depth\:\:INT,
                    $param_searches\:\:TEXT,
                    $param_statuses\:\:INT[],
                    $param_locations\:\:INT[],
                    $param_audience\:\:TEXT[],
                    $param_language\:\:TEXT[],
                    $param_lit_form\:\:TEXT[],
                    $param_types\:\:TEXT[],
                    $param_forms\:\:TEXT[],
                    $param_vformats\:\:TEXT[],
                    $param_bib_level\:\:TEXT[],
                    $param_before\:\:TEXT,
                    $param_after\:\:TEXT,
                    $param_during\:\:TEXT,
                    $param_between\:\:TEXT[],
                    $param_pref_lang\:\:TEXT,
                    $param_pref_lang_multiplier\:\:REAL,
                    $param_sort\:\:TEXT,
                    $param_sort_desc\:\:BOOL,
                    $metarecord\:\:BOOL,
                    $staff\:\:BOOL,
                    $param_rel_limit\:\:INT,
                    $param_chk_limit\:\:INT,
                    $param_skip_chk\:\:INT
                );
    SQL

    $sth->execute;

    my $recs = $sth->fetchall_arrayref({});
    my $summary_row = pop @$recs;

    my $total    = $$summary_row{total};
    my $checked  = $$summary_row{checked};
    my $visible  = $$summary_row{visible};
    my $deleted  = $$summary_row{deleted};
    my $excluded = $$summary_row{excluded};

    my $estimate = $visible;
    if ( $total > $checked && $checked ) {

        $$summary_row{hit_estimate} = FTS_paging_estimate($self, $client, $checked, $visible, $excluded, $deleted, $total);
        $estimate = $$summary_row{estimated_hit_count} = $$summary_row{hit_estimate}{$estimation_strategy};

    }

    delete $$summary_row{id};
    delete $$summary_row{rel};
    delete $$summary_row{record};

    $client->respond( $summary_row );

	$log->debug("Search yielded ".scalar(@$recs)." checked, visible results with an approximate visible total of $estimate.",DEBUG);

	for my $rec (@$recs[$offset .. $offset + $limit - 1]) {
        delete $$rec{checked};
        delete $$rec{visible};
        delete $$rec{excluded};
        delete $$rec{deleted};
        delete $$rec{total};
        $$rec{rel} = sprintf('%0.3f',$$rec{rel});

		$client->respond( $rec );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.staged.search_fts",
	method		=> 'staged_fts',
	api_level	=> 0,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.staged.search_fts.staff",
	method		=> 'staged_fts',
	api_level	=> 0,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.multiclass.staged.search_fts",
	method		=> 'staged_fts',
	api_level	=> 0,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.multiclass.staged.search_fts.staff",
	method		=> 'staged_fts',
	api_level	=> 0,
	stream		=> 1,
	cachable	=> 1,
);

sub FTS_paging_estimate {
    my $self   = shift;
    my $client = shift;

    my $checked  = shift;
    my $visible  = shift;
    my $excluded = shift;
    my $deleted  = shift;
    my $total    = shift;

    my $deleted_ratio = $deleted / $checked;
    my $delete_adjusted_total = $total - ( $total * $deleted_ratio );

    my $exclusion_ratio = $excluded / $checked;
    my $delete_adjusted_exclusion_ratio = $checked - $deleted ? $excluded / ($checked - $deleted) : 1;

    my $inclusion_ratio = $visible / $checked;
    my $delete_adjusted_inclusion_ratio = $checked - $deleted ? $visible / ($checked - $deleted) : 0;

    return {
        exclusion                   => int($delete_adjusted_total - ( $delete_adjusted_total * $exclusion_ratio )),
        inclusion                   => int($delete_adjusted_total * $inclusion_ratio),
        delete_adjusted_exclusion   => int($delete_adjusted_total - ( $delete_adjusted_total * $delete_adjusted_exclusion_ratio )),
        delete_adjusted_inclusion   => int($delete_adjusted_total * $delete_adjusted_inclusion_ratio)
    };
}
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.fts_paging_estimate",
	method		=> 'FTS_paging_estimate',
    argc        => 5,
    strict      => 1,
	api_level	=> 1,
    signature   => {
        'return'=> q#
            Hash of estimation values based on four variant estimation strategies:
                exclusion -- Estimate based on the ratio of excluded records on the current superpage;
                inclusion -- Estimate based on the ratio of visible records on the current superpage;
                delete_adjusted_exclusion -- Same as exclusion strategy, but the ratio is adjusted by deleted count;
                delete_adjusted_inclusion -- Same as inclusion strategy, but the ratio is adjusted by deleted count;
        #,
        desc    => q#
            Helper method used to determin the approximate number of
            hits for a search that spans multiple superpages.  For
            sparse superpages, the inclusion estimate will likely be the
            best estimate.  The exclusion strategy is the original, but
            inclusion is the default.
        #,
        params  => [
            {   name    => 'checked',
                desc    => 'Number of records check -- nominally the size of a superpage, or a remaining amount from the last superpage.',
                type    => 'number'
            },
            {   name    => 'visible',
                desc    => 'Number of records visible to the search location on the current superpage.',
                type    => 'number'
            },
            {   name    => 'excluded',
                desc    => 'Number of records excluded from the search location on the current superpage.',
                type    => 'number'
            },
            {   name    => 'deleted',
                desc    => 'Number of deleted records on the current superpage.',
                type    => 'number'
            },
            {   name    => 'total',
                desc    => 'Total number of records up to check_limit (superpage_size * max_superpages).',
                type    => 'number'
            }
        ]
    }
);


sub xref_count {
    my $self   = shift;
    my $client = shift;
    my $args   = shift;

    my $term  = $$args{term};
    my $limit = $$args{max} || 1;
    my $min   = $$args{min} || 1;
	my @classes = @{$$args{class}};

	$limit = $min if ($min > $limit);

	if (!@classes) {
		@classes = ( qw/ title author subject series keyword / );
	}

	my %matches;
	my $bre_table = biblio::record_entry->table;
	my $cn_table  = asset::call_number->table;
	my $cp_table  = asset::copy->table;

	for my $search_class ( @classes ) {

		my $class = $_cdbi->{$search_class};
		my $search_table = $class->table;

		my ($index_col) = $class->columns('FTS');
		$index_col ||= 'value';

		
		my $where = OpenILS::Application::Storage::FTS
			->compile($search_class => $term, $search_class.'.value', "$search_class.$index_col")
			->sql_where_clause;

		my $SQL = <<"		SQL";
			SELECT	COUNT(DISTINCT X.source)
			  FROM	(SELECT	$search_class.source
				  FROM	$search_table $search_class
					JOIN $bre_table b ON (b.id = $search_class.source)
				  WHERE	$where
				  	AND NOT b.deleted
					AND b.active
				  LIMIT $limit) X
			  HAVING COUNT(DISTINCT X.source) >= $min;
		SQL

		my $res = $class->db_Main->selectrow_arrayref( $SQL );
		$matches{$search_class} = $res ? $res->[0] : 0;
	}

	return \%matches;
}
__PACKAGE__->register_method(
    api_name  => "open-ils.storage.search.xref",
    method    => 'xref_count',
    api_level => 1,
);

# Takes an abstract query object and recursively turns it back into a string
# for QueryParser.
sub abstract_query2str {
    my ($self, $conn, $query) = @_;

    return QueryParser::Canonicalize::abstract_query2str_impl($query, 0);
}

__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.query_parser.abstract_query.canonicalize",
	method		=> "abstract_query2str",
	api_level	=> 1,
    signature   => {
        params  => [
            {desc => q/
Abstract query parser object, with complete config data. For example input,
see the 'abstract_query' part of the output of an API call like
open-ils.search.biblio.multiclass.query, when called with the return_abstract
flag set to true./,
                type => "object"}
        ],
        return => { type => "string", desc => "String representation of abstract query object" }
    }
);

sub str2abstract_query {
    my ($self, $conn, $query, $qp_opts, $with_config) = @_;

    my %use_opts = ( # reasonable defaults? should these even be hardcoded here?
        superpage => 1,
        superpage_size => 1000,
        core_limit => 25000,
        query => $query,
        (ref $opts eq 'HASH' ? %$opts : ())
    );

    $with_config ||= 0;

    # grab the query parser and initialize it
    my $parser = $OpenILS::Application::Storage::QParser;
    $parser->use;

    _initialize_parser($parser) unless $parser->initialization_complete;

    my $query = $parser->new(%use_opts)->parse;

    return $query->parse_tree->to_abstract_query(with_config => $with_config);
}

__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.query_parser.abstract_query.from_string",
	method		=> "str2abstract_query",
	api_level	=> 1,
    signature   => {
        params  => [
            {desc => "Query", type => "string"},
            {desc => q/Arguments for initializing QueryParser (optional)/,
                type => "object"},
            {desc => q/Flag enabling inclusion of QP config in returned object (optional, default false)/,
                type => "bool"}
        ],
        return => { type => "object", desc => "abstract representation of query parser query" }
    }
);

sub query_parser_fts {
    my $self = shift;
    my $client = shift;
    my %args = @_;


    # grab the query parser and initialize it
    my $parser = $OpenILS::Application::Storage::QParser;
    $parser->use;

    _initialize_parser($parser) unless $parser->initialization_complete;

    # populate the locale/language map
    if (!$locale_map{COMPLETE}) {

        my @locales = config::i18n_locale->search_where({ code => { '<>' => '' } });
        for my $locale ( @locales ) {
            $locale_map{lc($locale->code)} = $locale->marc_code;
        }
        $locale_map{COMPLETE} = 1;

    }

    # I hope we have a query!
	if (! $args{query} ) {
		die "No query was passed to ".$self->api_name;
	}

    my $default_CD_modifiers = OpenSRF::Utils::SettingsClient->new->config_value(
        apps => 'open-ils.search' => app_settings => 'default_CD_modifiers'
    );

    # Protect against empty / missing default_CD_modifiers setting
    if ($default_CD_modifiers and !ref($default_CD_modifiers)) {
        $args{query} = "$default_CD_modifiers $args{query}";
    }

    my $simple_plan = $args{_simple_plan};
    # remove bad chunks of the %args hash
    for my $bad ( grep { /^_/ } keys(%args)) {
        delete($args{$bad});
    }


    # parse the query and supply any query-level %arg-based defaults
    # we expect, and make use of, query, superpage, superpage_size, debug and core_limit args
    my $query = $parser->new( %args )->parse;

    my $config = OpenSRF::Utils::SettingsClient->new();

    # set the locale-based default preferred location
    if (!$query->parse_tree->find_filter('preferred_language')) {
        $parser->default_preferred_language( $args{preferred_language} );

        if (!$parser->default_preferred_language) {
		    my $ses_locale = $client->session ? $client->session->session_locale : '';
            $parser->default_preferred_language( $locale_map{ lc($ses_locale) } );
        }

        if (!$parser->default_preferred_language) { # still nothing...
            my $tmp_dpl = $config->config_value(
                apps => 'open-ils.search' => app_settings => 'default_preferred_language'
            ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language'
            );

            $parser->default_preferred_language( $tmp_dpl )
        }
    }


    # set the global default language multiplier
    if (!$query->parse_tree->find_filter('preferred_language_weight') and !$query->parse_tree->find_filter('preferred_language_multiplier')) {
        my $tmp_dplw;

        if ($tmp_dplw = $args{preferred_language_weight} || $args{preferred_language_multiplier} ) {
            $parser->default_preferred_language_multiplier($tmp_dplw);

        } else {
            $tmp_dplw = $config->config_value(
                apps => 'open-ils.search' => app_settings => 'default_preferred_language_weight'
            ) || $config->config_value(
                apps => 'open-ils.storage' => app_settings => 'default_preferred_language_weight'
            );

            $parser->default_preferred_language_multiplier( $tmp_dplw );
        }
    }

    # gather the site, if one is specified, defaulting to the in-query version
	my $ou = $args{org_unit};
	if (my ($filter) = $query->parse_tree->find_filter('site')) {
            $ou = $filter->args->[0] if (@{$filter->args});
    }
    $ou = actor::org_unit->search( { shortname => $ou } )->next->id if ($ou and $ou !~ /^(-)?\d+$/);

    # gather lasso, as with $ou
	my $lasso = $args{lasso};
	if (my ($filter) = $query->parse_tree->find_filter('lasso')) {
            $lasso = $filter->args->[0] if (@{$filter->args});
    }
	$lasso = actor::org_lasso->search( { name => $lasso } )->next->id if ($lasso and $lasso !~ /^\d+$/);
    $lasso = -$lasso if ($lasso);


#    # XXX once we have org_unit containers, we can make user-defined lassos .. WHEEE
#    # gather user lasso, as with $ou and lasso
#    my $mylasso = $args{my_lasso};
#    if (my ($filter) = $query->parse_tree->find_filter('my_lasso')) {
#            $mylasso = $filter->args->[0] if (@{$filter->args});
#    }
#    $mylasso = actor::org_unit->search( { name => $mylasso } )->next->id if ($mylasso and $mylasso !~ /^\d+$/);


    # if we have a lasso, go with that, otherwise ... ou
    $ou = $lasso if ($lasso);

    # gather the preferred OU, if one is specified, as with $ou
    my $pref_ou = $args{pref_ou};
	$log->info("pref_ou = $pref_ou");
	if (my ($filter) = $query->parse_tree->find_filter('pref_ou')) {
            $pref_ou = $filter->args->[0] if (@{$filter->args});
    }
    $pref_ou = actor::org_unit->search( { shortname => $pref_ou } )->next->id if ($pref_ou and $pref_ou !~ /^(-)?\d+$/);

    # get the default $ou if we have nothing
	$ou = actor::org_unit->search( { parent_ou => undef } )->next->id if (!$ou and !$lasso and !$mylasso);


    # XXX when user lassos are here, check to make sure we don't have one -- it'll be passed in the depth, with an ou of 0
    # gather the depth, if one is specified, defaulting to the in-query version
	my $depth = $args{depth};
	if (my ($filter) = $query->parse_tree->find_filter('depth')) {
            $depth = $filter->args->[0] if (@{$filter->args});
    }
	$depth = actor::org_unit->search_where( [{ name => $depth },{ opac_label => $depth }], {limit => 1} )->next->id if ($depth and $depth !~ /^\d+$/);


    # gather the limit or default to 10
	my $limit = $args{check_limit} || 'NULL';
	if (my ($filter) = $query->parse_tree->find_filter('limit')) {
            $limit = $filter->args->[0] if (@{$filter->args});
    }
	if (my ($filter) = $query->parse_tree->find_filter('check_limit')) {
            $limit = $filter->args->[0] if (@{$filter->args});
    }


    # gather the offset or default to 0
	my $offset = $args{skip_check} || $args{offset} || 0;
	if (my ($filter) = $query->parse_tree->find_filter('offset')) {
            $offset = $filter->args->[0] if (@{$filter->args});
    }
	if (my ($filter) = $query->parse_tree->find_filter('skip_check')) {
            $offset = $filter->args->[0] if (@{$filter->args});
    }


    # gather the estimation strategy or default to inclusion
    my $estimation_strategy = $args{estimation_strategy} || 'inclusion';
	if (my ($filter) = $query->parse_tree->find_filter('estimation_strategy')) {
            $estimation_strategy = $filter->args->[0] if (@{$filter->args});
    }


    # gather the estimation strategy or default to inclusion
    my $core_limit = $args{core_limit};
	if (my ($filter) = $query->parse_tree->find_filter('core_limit')) {
            $core_limit = $filter->args->[0] if (@{$filter->args});
    }


    # gather statuses, and then forget those if we have an #available modifier
    my @statuses;
    if (my ($filter) = $query->parse_tree->find_filter('statuses')) {
        @statuses = @{$filter->args} if (@{$filter->args});
    }
    @statuses = (0,7,12) if ($query->parse_tree->find_modifier('available'));


    # gather locations
    my @location;
    if (my ($filter) = $query->parse_tree->find_filter('locations')) {
        @location = @{$filter->args} if (@{$filter->args});
    }

    # gather location_groups
    if (my ($filter) = $query->parse_tree->find_filter('location_groups')) {
        my @loc_groups = @{$filter->args} if (@{$filter->args});
        
        # collect the mapped locations and add them to the locations() filter
        if (@loc_groups) {

            my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );
            my $maps = $cstore->request(
                'open-ils.cstore.direct.asset.copy_location_group_map.search.atomic',
                {lgroup => \@loc_groups})->gather(1);

            push(@location, $_->location) for @$maps;
        }
    }


    my $param_check = $limit || $query->superpage_size || 'NULL';
    my $param_offset = $offset || 'NULL';
    my $param_limit = $core_limit || 'NULL';

    my $sp = $query->superpage || 1;
    if ($sp > 1) {
        $param_offset = ($sp - 1) * $sp_size;
    }

	my $param_search_ou = $ou;
	my $param_depth = $depth; $param_depth = 'NULL' unless (defined($depth) and length($depth) > 0 );
	my $param_core_query = "\$core_query_$$\$" . $query->parse_tree->toSQL . "\$core_query_$$\$";
	my $param_statuses = '$${' . join(',', map { s/\$//go; "\"$_\""} @statuses) . '}$$';
	my $param_locations = '$${' . join(',', map { s/\$//go; "\"$_\""} @location) . '}$$';
	my $staff = ($self->api_name =~ /staff/ or $query->parse_tree->find_modifier('staff')) ? "'t'" : "'f'";
	my $metarecord = ($self->api_name =~ /metabib/ or $query->parse_tree->find_modifier('metabib') or $query->parse_tree->find_modifier('metarecord')) ? "'t'" : "'f'";
	my $param_pref_ou = $pref_ou || 'NULL';

	my $sth = metabib::metarecord_source_map->db_Main->prepare(<<"    SQL");
        SELECT  * -- bib search: $args{query}
          FROM  search.query_parser_fts(
                    $param_search_ou\:\:INT,
                    $param_depth\:\:INT,
                    $param_core_query\:\:TEXT,
                    $param_statuses\:\:INT[],
                    $param_locations\:\:INT[],
                    $param_offset\:\:INT,
                    $param_check\:\:INT,
                    $param_limit\:\:INT,
                    $metarecord\:\:BOOL,
                    $staff\:\:BOOL,
                    $param_pref_ou\:\:INT
                );
    SQL

    $sth->execute;

    my $recs = $sth->fetchall_arrayref({});
    my $summary_row = pop @$recs;

    my $total    = $$summary_row{total};
    my $checked  = $$summary_row{checked};
    my $visible  = $$summary_row{visible};
    my $deleted  = $$summary_row{deleted};
    my $excluded = $$summary_row{excluded};

    my $estimate = $visible;
    if ( $total > $checked && $checked ) {

        $$summary_row{hit_estimate} = FTS_paging_estimate($self, $client, $checked, $visible, $excluded, $deleted, $total);
        $estimate = $$summary_row{estimated_hit_count} = $$summary_row{hit_estimate}{$estimation_strategy};

    }

    delete $$summary_row{id};
    delete $$summary_row{rel};
    delete $$summary_row{record};

    if (defined($simple_plan)) {
        $$summary_row{complex_query} = $simple_plan ? 0 : 1;
    } else {
        $$summary_row{complex_query} = $query->simple_plan ? 0 : 1;
    }

    $client->respond( $summary_row );

	$log->debug("Search yielded ".scalar(@$recs)." checked, visible results with an approximate visible total of $estimate.",DEBUG);

	for my $rec (@$recs) {
        delete $$rec{checked};
        delete $$rec{visible};
        delete $$rec{excluded};
        delete $$rec{deleted};
        delete $$rec{total};
        $$rec{rel} = sprintf('%0.3f',$$rec{rel});

		$client->respond( $rec );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.query_parser_search",
	method		=> 'query_parser_fts',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

sub query_parser_fts_wrapper {
	my $self = shift;
	my $client = shift;
	my %args = @_;

 	$log->debug("Entering compatability wrapper function for old-style staged search", DEBUG);
    # grab the query parser and initialize it
    my $parser = $OpenILS::Application::Storage::QParser;
    $parser->use;

    if (!$parser->initialization_complete) {
        my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );
        $parser->initialize(
            config_record_attr_index_norm_map =>
                $cstore->request(
                    'open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic',
                    { id => { "!=" => undef } },
                    { flesh => 1, flesh_fields => { crainm => [qw/norm/] }, order_by => [{ class => "crainm", field => "pos" }] }
                )->gather(1),
            search_relevance_adjustment         =>
                $cstore->request(
                    'open-ils.cstore.direct.search.relevance_adjustment.search.atomic',
                    { id => { "!=" => undef } }
                )->gather(1),
            config_metabib_field                =>
                $cstore->request(
                    'open-ils.cstore.direct.config.metabib_field.search.atomic',
                    { id => { "!=" => undef } }
                )->gather(1),
            config_metabib_search_alias         =>
                $cstore->request(
                    'open-ils.cstore.direct.config.metabib_search_alias.search.atomic',
                    { alias => { "!=" => undef } }
                )->gather(1),
            config_metabib_field_index_norm_map =>
                $cstore->request(
                    'open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic',
                    { id => { "!=" => undef } },
                    { flesh => 1, flesh_fields => { cmfinm => [qw/norm/] }, order_by => [{ class => "cmfinm", field => "pos" }] }
                )->gather(1),
            config_record_attr_definition       =>
                $cstore->request(
                    'open-ils.cstore.direct.config.record_attr_definition.search.atomic',
                    { name => { "!=" => undef } }
                )->gather(1),
        );

        $cstore->disconnect;
        die("Cannot initialize $parser!") unless ($parser->initialization_complete);
    }

	if (! scalar( keys %{$args{searches}} )) {
		die "No search arguments were passed to ".$self->api_name;
	}

 	$log->debug("Constructing QueryParser query from staged search hash ...", DEBUG);
    my $base_query = '';
    for my $sclass ( keys %{$args{searches}} ) {
 	    $log->debug(" --> staged search key: $sclass --> term: $args{searches}{$sclass}{term}", DEBUG);
        $base_query .= " $sclass: $args{searches}{$sclass}{term}";
    }

    my $query = $base_query;
    $log->debug("Full base query: $base_query", DEBUG);

    $query = "$args{facets} $query" if  ($args{facets});

    if (!$locale_map{COMPLETE}) {

        my @locales = config::i18n_locale->search_where({ code => { '<>' => '' } });
        for my $locale ( @locales ) {
            $locale_map{lc($locale->code)} = $locale->marc_code;
        }
        $locale_map{COMPLETE} = 1;

    }

    my $base_plan = $parser->new( query => $base_query )->parse;

    $query = "$query preferred_language($args{preferred_language})"
        if ($args{preferred_language} and !$base_plan->parse_tree->find_filter('preferred_language'));
    $query = "$query preferred_language_weight($args{preferred_language_weight})"
        if ($args{preferred_language_weight} and !$base_plan->parse_tree->find_filter('preferred_language_weight') and !$base_plan->parse_tree->find_filter('preferred_language_multiplier'));


    # we add these to the end of the query (last-wins) because in wrapper mode we want to retain the behaviour
    # of separately specified options taking precidenc -- IOW, the user should not be able to cause a change in,
    # say, superpage size by adjusting the query string.
    $query = "$query estimation_strategy($args{estimation_strategy})" if ($args{estimation_strategy});
    $query = "$query site($args{org_unit})" if ($args{org_unit});
    $query = "$query depth($args{depth})" if (defined($args{depth}));
    $query = "$query sort($args{sort})" if ($args{sort});
    $query = "$query limit($args{limit})" if ($args{limit});
    $query = "$query core_limit($args{core_limit})" if ($args{core_limit});
    $query = "$query skip_check($args{skip_check})" if ($args{skip_check});
    $query = "$query superpage($args{superpage})" if ($args{superpage});
    $query = "$query offset($args{offset})" if ($args{offset});
    $query = "$query #metarecord" if ($self->api_name =~ /metabib/);
    $query = "$query #available" if ($args{available});
    $query = "$query #descending" if ($args{sort_dir} && $args{sort_dir} =~ /^d/i);
    $query = "$query #staff" if ($self->api_name =~ /staff/);
    $query = "$query before($args{before})" if (defined($args{before}) and $args{before} =~ /^\d+$/);
    $query = "$query after($args{after})" if (defined($args{after}) and $args{after} =~ /^\d+$/);
    $query = "$query during($args{during})" if (defined($args{during}) and $args{during} =~ /^\d+$/);
    $query = "$query between($args{between}[0],$args{between}[1])"
        if ( ref($args{between}) and @{$args{between}} == 2 and $args{between}[0] =~ /^\d+$/ and $args{between}[1] =~ /^\d+$/ );


	my (@between,@statuses,@locations,@location_groups,@types,@forms,@lang,@aud,@lit_form,@vformats,@bib_level);

	# XXX legacy format and item type support
	if ($args{format}) {
		my ($t, $f) = split '-', $args{format};
		$args{item_type} = [ split '', $t ];
		$args{item_form} = [ split '', $f ];
	}

    for my $filter ( qw/locations location_groups statuses between audience language lit_form item_form item_type bib_level vr_format/ ) {
    	if (my $s = $args{$filter}) {
    		$s = [$s] if (!ref($s));

    		my @filter_list = @$s;

            next if ($filter eq 'between' and scalar(@filter_list) != 2);
            next if (@filter_list == 0);

            my $filter_string = join ',', @filter_list;
            $query = "$query $filter($filter_string)";
	    }
    }

    $log->debug("Full QueryParser query: $query", DEBUG);

    return query_parser_fts($self, $client, query => $query, _simple_plan => $base_plan->simple_plan );
}
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.staged.search_fts",
	method		=> 'query_parser_fts_wrapper',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.biblio.multiclass.staged.search_fts.staff",
	method		=> 'query_parser_fts_wrapper',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.multiclass.staged.search_fts",
	method		=> 'query_parser_fts_wrapper',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.metabib.multiclass.staged.search_fts.staff",
	method		=> 'query_parser_fts_wrapper',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);


1;

