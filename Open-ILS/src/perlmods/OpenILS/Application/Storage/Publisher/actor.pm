package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::actor;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;

use DateTime;           
use DateTime::Format::ISO8601;  
                                                
						                                                
my $_dt_parser = DateTime::Format::ISO8601->new;    

my $log = 'OpenSRF::Utils::Logger';

sub new_usergroup_id {
	return actor::user->db_Main->selectrow_array("select nextval('actor.usr_usrgroup_seq'::regclass)");
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.group_id.new',
	api_level	=> 1,
	method		=> 'new_usergroup_id',
);

sub usr_total_owed {
	my $self = shift;
	my $client = shift;
	my $usr = shift;

	my $sql = <<"	SQL";
			SELECT	x.usr,
					SUM(COALESCE((SELECT SUM(b.amount) FROM money.billing b WHERE b.voided IS FALSE AND b.xact = x.id),0.0)) -
						SUM(COALESCE((SELECT SUM(p.amount) FROM money.payment p WHERE p.voided IS FALSE AND p.xact = x.id),0.0))
			  FROM	money.billable_xact x
			  WHERE	x.usr = ? AND x.xact_finish IS NULL
			  GROUP BY 1
	SQL

	my (undef,$val) = actor::user->db_Main->selectrow_array($sql, {}, $usr);

	return $val;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.total_owed',
	api_level	=> 1,
	method		=> 'usr_total_owed',
);

sub usr_breakdown_out {
	my $self = shift;
	my $client = shift;
	my $usr = shift;

	my $out_sql = <<"	SQL";
			SELECT	id
			  FROM	action.circulation
			  WHERE	usr = ?
                    AND checkin_time IS NULL
                    AND (  (fine_interval >= '1 day' AND due_date >= 'today')
                        OR (fine_interval < '1 day'  AND due_date > 'now'   ))
                    AND (stop_fines IS NULL
                        OR stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE'))
	SQL

	my $out = actor::user->db_Main->selectcol_arrayref($out_sql, {}, $usr);

	my $od_sql = <<"	SQL";
			SELECT	id
			  FROM	action.circulation
			  WHERE	usr = ?
                    AND checkin_time IS NULL
                    AND (  (fine_interval >= '1 day' AND due_date < 'today')
                        OR (fine_interval < '1 day'  AND due_date < 'now'  ))
                    AND (stop_fines IS NULL
                        OR stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE'))
	SQL

	my $od = actor::user->db_Main->selectcol_arrayref($od_sql, {}, $usr);

	my $lost_sql = <<"	SQL";
			SELECT	id
			  FROM	action.circulation
			  WHERE	usr = ? AND checkin_time IS NULL AND xact_finish IS NULL AND stop_fines = 'LOST'
	SQL

	my $lost = actor::user->db_Main->selectcol_arrayref($lost_sql, {}, $usr);

	my $cl_sql = <<"	SQL";
			SELECT	id
			  FROM	action.circulation
			  WHERE	usr = ? AND checkin_time IS NULL AND stop_fines = 'CLAIMSRETURNED'
	SQL

	my $cl = actor::user->db_Main->selectcol_arrayref($cl_sql, {}, $usr);

	my $lo_sql = <<"	SQL";
			SELECT	id
			  FROM	action.circulation
			  WHERE	usr = ? AND checkin_time IS NULL AND stop_fines = 'LONGOVERDUE'
	SQL

	my $lo = actor::user->db_Main->selectcol_arrayref($lo_sql, {}, $usr);

	if ($self->api_name =~/count$/o) {
		return {	total	=> scalar(@$out) + scalar(@$od) + scalar(@$lost) + scalar(@$cl) + scalar(@$lo),
					out		=> scalar(@$out),
					overdue	=> scalar(@$od),
					lost	=> scalar(@$lost),
					claims_returned	=> scalar(@$cl),
					long_overdue		=> scalar(@$lo),
		};
	}

	return {	out		=> $out,
				overdue	=> $od,
				lost	=> $lost,
				claims_returned	=> $cl,
				long_overdue		=> $lo,
	};
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.checked_out',
	api_level	=> 1,
	method		=> 'usr_breakdown_out',
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.checked_out.count',
	api_level	=> 1,
	method		=> 'usr_breakdown_out',
);

sub usr_total_out {
	my $self = shift;
	my $client = shift;
	my $usr = shift;

	my $sql = <<"	SQL";
			SELECT	count(*)
			  FROM	action.circulation
			  WHERE	usr = ? AND checkin_time IS NULL
	SQL

	my ($val) = actor::user->db_Main->selectrow_array($sql, {}, $usr);

	return $val;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.total_out',
	api_level	=> 1,
	method		=> 'usr_total_out',
);

sub calc_proximity {
	my $self = shift;
	my $client = shift;

	local $OpenILS::Application::Storage::WRITE = 1;

	my $delete_sql = <<"	SQL";
		DELETE FROM actor.org_unit_proximity;
	SQL

	my $insert_sql = <<"	SQL";
		INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
			SELECT	l.id,
				r.id,
				actor.org_unit_proximity(l.id,r.id)
			  FROM	actor.org_unit l,
				actor.org_unit r;
	SQL

	actor::org_unit_proximity->db_Main->do($delete_sql);
	actor::org_unit_proximity->db_Main->do($insert_sql);

	return 1;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.refresh_proximity',
	api_level	=> 1,
	method		=> 'calc_proximity',
);


sub org_closed_overlap {
	my $self = shift;
	my $client = shift;
	my $ou = shift;
	my $date = shift;
	my $direction = shift || 0;
	my $no_hoo = shift || 0;

	return undef unless ($date && $ou);

	my $t = actor::org_unit::closed_date->table;
	my $sql = <<"	SQL";
		SELECT	*
		  FROM	$t
		  WHERE	? between close_start and close_end
			AND org_unit = ?
		  ORDER BY close_start ASC, close_end DESC
		  LIMIT 1
	SQL

	$date = clense_ISO8601($date);
	my ($begin, $end) = ($date,$date);

	my $hoo = actor::org_unit::hours_of_operation->retrieve($ou);

	if (my $closure = actor::org_unit::closed_date->db_Main->selectrow_hashref( $sql, {}, $date, $ou )) {
		$begin = clense_ISO8601($closure->{close_start});
		$end = clense_ISO8601($closure->{close_end});

		if ( $direction <= 0 ) {
			$before = $_dt_parser->parse_datetime( $begin );
			$before->subtract( minutes => 1 );

			while ( my $_b = org_closed_overlap($self, $client, $ou, $before->iso8601, -1, 1 ) ) {
				$before = $_dt_parser->parse_datetime( clense_ISO8601($_b->{start}) );
			}
			$begin = clense_ISO8601($before->iso8601);
		}

		if ( $direction >= 0 ) {
			$after = $_dt_parser->parse_datetime( $end );
			$after->add( minutes => 1 );

			while ( my $_a = org_closed_overlap($self, $client, $ou, $after->iso8601, 1, 1 ) ) {
				$after = $_dt_parser->parse_datetime( clense_ISO8601($_a->{end}) );
			}
			$end = clense_ISO8601($after->iso8601);
		}
	}

	if ( !$no_hoo ) {
		if ( $hoo ) {

			if ( $direction <= 0 ) {
				my $begin_dow = $_dt_parser->parse_datetime( $begin )->day_of_week_0;
				my $begin_open_meth = "dow_".$begin_dow."_open";
				my $begin_close_meth = "dow_".$begin_dow."_close";

				my $count = 1;
				while ($hoo->$begin_open_meth eq '00:00:00' and $hoo->$begin_close_meth eq '00:00:00') {
					$begin = clense_ISO8601($_dt_parser->parse_datetime( $begin )->subtract( days => 1)->iso8601);
					$begin_dow++;
					$begin_dow %= 7;
					$count++;
					last if ($count > 6);
					$begin_open_meth = "dow_".$begin_dow."_open";
					$begin_close_meth = "dow_".$begin_dow."_close";
				}

				if (my $closure = actor::org_unit::closed_date->db_Main->selectrow_hashref( $sql, {}, $begin, $ou )) {
					$before = $_dt_parser->parse_datetime( $begin );
					$before->subtract( minutes => 1 );
					while ( my $_b = org_closed_overlap($self, $client, $ou, $before->iso8601, -1 ) ) {
						$before = $_dt_parser->parse_datetime( clense_ISO8601($_b->{start}) );
					}
				}
			}
	
			if ( $direction >= 0 ) {
				my $end_dow = $_dt_parser->parse_datetime( $end )->day_of_week_0;
				my $end_open_meth = "dow_".$end_dow."_open";
				my $end_close_meth = "dow_".$end_dow."_close";
	
				$count = 1;
				while ($hoo->$end_open_meth eq '00:00:00' and $hoo->$end_close_meth eq '00:00:00') {
					$end = clense_ISO8601($_dt_parser->parse_datetime( $end )->add( days => 1)->iso8601);
					$end_dow++;
					$end_dow %= 7;
					$count++;
					last if ($count > 6);
					$end_open_meth = "dow_".$end_dow."_open";
					$end_close_meth = "dow_".$end_dow."_close";
				}

				if (my $closure = actor::org_unit::closed_date->db_Main->selectrow_hashref( $sql, {}, $end, $ou )) {
					$after = $_dt_parser->parse_datetime( $end );
					$after->add( minutes => 1 );

					while ( my $_a = org_closed_overlap($self, $client, $ou, $after->iso8601, 1 ) ) {
						$after = $_dt_parser->parse_datetime( clense_ISO8601($_a->{end}) );
					}
					$end = clense_ISO8601($after->iso8601);
				}
			}

		}
	}

	if ($begin eq $date && $end eq $date) {
		return undef;
	}

	return { start => $begin, end => $end };
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.closed_date.overlap',
	api_level	=> 1,
	method		=> 'org_closed_overlap',
);

sub user_by_barcode {
	my $self = shift;
	my $client = shift;
	my @barcodes = shift;

	return undef unless @barcodes;

	for my $card ( actor::card->search( { barcode => @barcodes } ) ) {
		next unless $card;
		if (@barcodes == 1) {
			return $card->usr->to_fieldmapper;
		}
		$client->respond( $card->usr->to_fieldmapper);
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.user.search.barcode',
	api_level	=> 1,
	method		=> 'user_by_barcode',
	stream		=> 1,
	cachable	=> 1,
);

sub lost_barcodes {
	my $self = shift;
	my $client = shift;

	my $c = actor::card->table;
	my $p = actor::user->table;

	my $sql = "SELECT c.barcode FROM $c c JOIN $p p ON (c.usr = p.id) WHERE p.card <> c.id";

	my $list = actor::user->db_Main->selectcol_arrayref($sql);
	for my $bc ( @$list ) {
		$client->respond($bc);
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.lost_barcodes',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'lost_barcodes',
	signature	=> <<'	NOTE',
		Returns an array of barcodes that belong to lost cards.
		@return array of barcodes
	NOTE
);

sub expired_barcodes {
	my $self = shift;
	my $client = shift;

	my $c = actor::card->table;
	my $p = actor::user->table;

	my $sql = "SELECT c.barcode FROM $c c JOIN $p p ON (c.usr = p.id) WHERE p.expire_date < CURRENT_DATE";

	my $list = actor::user->db_Main->selectcol_arrayref($sql);
	for my $bc ( @$list ) {
		$client->respond($bc);
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.expired_barcodes',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'expired_barcodes',
	signature	=> <<'	NOTE',
		Returns an array of barcodes that are currently expired.
		@return array of barcodes
	NOTE
);

sub barred_barcodes {
	my $self = shift;
	my $client = shift;

	my $c = actor::card->table;
	my $p = actor::user->table;

	my $sql = "SELECT c.barcode FROM $c c JOIN $p p ON (c.usr = p.id) WHERE p.barred IS TRUE";

	my $list = actor::user->db_Main->selectcol_arrayref($sql);
	for my $bc ( @$list ) {
		$client->respond($bc);
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.barred_barcodes',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'barred_barcodes',
	signature	=> <<'	NOTE',
		Returns an array of barcodes that are currently barred.
		@return array of barcodes
	NOTE
);

sub penalized_barcodes {
	my $self = shift;
	my $client = shift;
	my @ignore = @_;

	my $c = actor::card->table;
	my $p = actor::user_standing_penalty->table;

	my $sql = "SELECT c.barcode FROM $c c JOIN $p p USING (usr)";

	if (@ignore) {
		$sql .= ' WHERE penalty_type NOT IN ('. join(',', map { '?' } @ignore) . ')';
	}

	$sql .= ' GROUP BY c.barcode;';

	my $list = actor::user->db_Main->selectcol_arrayref($sql, {}, @ignore);
	for my $bc ( @$list ) {
		$client->respond($bc);
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.penalized_barcodes',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'penalized_barcodes',
	signature	=> <<'	NOTE',
		Returns an array of barcodes that have penalties not listed
		as a parameter.  Supply a list of any penalty types that should
		not stop a patron from checking out materials.

		@param ignore_list Penalty type to ignore
		@return array of barcodes
	NOTE
);


sub patron_search {
	my $self = shift;
	my $client = shift;
	my $search = shift;
	my $limit = shift || 1000;
	my $sort = shift;
	my $inactive = shift;
	my $ws_ou = shift;
	my $ws_ou_depth = shift || 0;

	my $strict_opt_in = OpenSRF::Utils::SettingsClient->new->config_value( share => user => 'opt_in' );

	$sort = ['family_name','first_given_name'] unless ($$sort[0]);
	push @$sort,'id';

	# group 0 = user
	# group 1 = address
	# group 2 = phone, ident

	my $usr = join ' AND ', map { "LOWER($_) ~ ?" } grep { ''.$$search{$_}{group} eq '0' } keys %$search;
	my @usrv = map { "^$$search{$_}{value}" } grep { ''.$$search{$_}{group} eq '0' } keys %$search;

	my $addr = join ' AND ', map { "LOWER($_) ~ ?" } grep { ''.$$search{$_}{group} eq '1' } keys %$search;
	my @addrv = map { "^$$search{$_}{value}" } grep { ''.$$search{$_}{group} eq '1' } keys %$search;

	my $pv = $$search{phone}{value};
	my $iv = $$search{ident}{value};
	my $nv = $$search{name}{value};

	my $phone = '';
	my @ps;
	my @phonev;
	if ($pv) {
		for my $p ( qw/day_phone evening_phone other_phone/ ) {
			push @ps, "LOWER($p) ~ ?";
			push @phonev, "^$pv";
		}
		$phone = '(' . join(' OR ', @ps) . ')';
	}

	my $ident = '';
	my @is;
	my @identv;
	if ($iv) {
		for my $i ( qw/ident_value ident_value2/ ) {
			push @is, "LOWER($i) ~ ?";
			push @identv, "^$iv";
		}
		$ident = '(' . join(' OR ', @is) . ')';
	}

	my $name = '';
	my @ns;
	my @namev;
	if (0 && $nv) {
		for my $n ( qw/first_given_name second_given_name family_name/ ) {
			push @ns, "LOWER($i) ~ ?";
			push @namev, "^$nv";
		}
		$name = '(' . join(' OR ', @ns) . ')';
	}

	my $usr_where = join ' AND ', grep { $_ } ($usr,$phone,$ident,$name);
	my $addr_where = $addr;


	my $u_table = actor::user->table;
	my $a_table = actor::user_address->table;
	my $opt_in_table = actor::usr_org_unit_opt_in->table;
	my $ou_table = actor::org_unit->table;

	my $u_select = "SELECT id as id FROM $u_table u WHERE $usr_where";
	my $a_select = "SELECT u.id as id FROM $a_table a JOIN $u_table u ON (u.mailing_address = a.id OR u.billing_address = a.id) WHERE $addr_where";

	my $clone_select = '';

	#$clone_select = "JOIN (SELECT cu.id as id FROM $a_table ca ".
	#		   "JOIN $u_table cu ON (cu.mailing_address = ca.id OR cu.billing_address = ca.id) ".
	#		   "WHERE $addr_where) AS clone ON (clone.id = users.id)" if ($addr_where);

	my $select = '';
	if ($usr_where) {
		if ($addr_where) {
			$select = "$u_select INTERSECT $a_select";
		} else {
			$select = $u_select;
		}
	} elsif ($addr_where) {
		$select = "$a_select";
	} else {
		return undef;
	}

	my $order_by = join ', ', map { 'LOWER(users.'. (split / /,$_)[0] . ') ' . (split / /,$_)[1] } @$sort;
	my $distinct_list = join ', ', map { 'LOWER(users.'. (split / /,$_)[0] . ')' } @$sort;

	if ($inactive) {
		$inactive = '';
	} else {
		$inactive = 'AND users.active = TRUE';
	}

	if (!$ws_ou) {  # XXX This should be required!!
		$ws_ou = actor::org_unit->search( { parent_ou => undef } )->next->id;
	}

	my $opt_in_join = '';
	my $opt_in_where = '';
	if (lc($strict_opt_in) eq 'true') {
		$opt_in_join = "LEFT JOIN $opt_in_table oi ON (oi.org_unit = $ws_ou AND users.id = oi.usr)";
		$opt_in_where = "AND (oi.id IS NOT NULL OR users.home_ou = $ws_ou)";
	}

	my $descendants = "actor.org_unit_descendants($ws_ou, $ws_ou_depth)";

	$select = <<"	SQL";
		SELECT	DISTINCT $distinct_list
		  FROM	$u_table AS users
			JOIN ($select) AS search ON (search.id = users.id)
			JOIN $descendants d ON (d.id = users.home_ou)
			$opt_in_join
			$clone_select
		  WHERE	users.deleted = FALSE
			$inactive
			$opt_in_where
		  ORDER BY $order_by
		  LIMIT $limit
	SQL

	return actor::user->db_Main->selectcol_arrayref($select, {Columns=>[scalar(@$sort)]}, map {lc($_)} (@usrv,@phonev,@identv,@namev,@addrv,@addrv));
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.user.crazy_search',
	api_level	=> 1,
	method		=> 'patron_search',
);

=comment not gonna use it...

sub fleshed_search {
	my $self = shift;
	my $client = shift;
	my $searches = shift;

	return undef unless (defined $searches);

	for my $usr ( actor::user->search( $searches ) ) {
		next unless $usr;
		$client->respond( flesh_user( $usr ) );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.actor.user.search',
	api_level	=> 1,
	method		=> 'fleshed_search',
	stream		=> 1,
	cachable	=> 1,
);

sub fleshed_search_like {
	my $self = shift;
	my $client = shift;
	my $searches = shift;

	return undef unless (defined $searches);

	for my $usr ( actor::user->search_like( $searches ) ) {
		next unless $usr;
		$client->respond( flesh_user( $usr ) );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.actor.user.search_like',
	api_level	=> 1,
	method		=> 'user_by_barcode',
	stream		=> 1,
	cachable	=> 1,
);

sub retrieve_fleshed_user {
	my $self = shift;
	my $client = shift;
	my @ids = shift;

	return undef unless @ids;

	@ids = ($ids[0]) unless ($self->api_name =~ /batch/o); 

	$client->respond( flesh_user( actor::user->retrieve( $_ ) ) ) for ( @ids );

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.actor.user.retrieve',
	api_level	=> 1,
	method		=> 'retrieve_fleshed_user',
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.actor.user.batch.retrieve',
	api_level	=> 1,
	method		=> 'retrieve_fleshed_user',
	stream		=> 1,
	cachable	=> 1,
);

sub flesh_user {
	my $usr = shift;


	my $standing = $usr->standing;
	my $profile = $usr->profile;
	my $ident_type = $usr->ident_type;
		
	my $maddress = $usr->mailing_address;
	my $baddress = $usr->billing_address;
	my $card = $usr->card;

	my @addresses = $usr->addresses;
	my @cards = $usr->cards;

	my $usr_fm = $usr->to_fieldmapper;
	$usr_fm->standing( $standing->to_fieldmapper );
	$usr_fm->profile( $profile->to_fieldmapper );
	$usr_fm->ident_type( $ident_type->to_fieldmapper );

	$usr_fm->card( $card->to_fieldmapper );
	$usr_fm->mailing_address( $maddress->to_fieldmapper ) if ($maddress);
	$usr_fm->billing_address( $baddress->to_fieldmapper ) if ($baddress);

	$usr_fm->cards( [ map { $_->to_fieldmapper } @cards ] );
	$usr_fm->addresses( [ map { $_->to_fieldmapper } @addresses ] );

	return $usr_fm;
}

=cut

sub org_unit_list {
	my $self = shift;
	my $client = shift;

	my $select =<<"	SQL";
	SELECT	*
	  FROM	actor.org_unit
	  ORDER BY CASE WHEN parent_ou IS NULL THEN 0 ELSE 1 END, name;
	SQL

	my $sth = actor::org_unit->db_Main->prepare_cached($select);
	$sth->execute;

	$client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.org_unit.retrieve.all',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'org_unit_list',
);

sub org_unit_type_list {
	my $self = shift;
	my $client = shift;

	my $select =<<"	SQL";
	SELECT	*
	  FROM	actor.org_unit_type
	  ORDER BY depth, name;
	SQL

	my $sth = actor::org_unit_type->db_Main->prepare_cached($select);
	$sth->execute;

	$client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit_type->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.org_unit_type.retrieve.all',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'org_unit_type_list',
);

sub org_unit_full_path {
	my $self = shift;
	my $client = shift;
	my @binds = @_;

	return undef unless (@binds);

	my $func = 'actor.org_unit_full_path(?)';
	$func = 'actor.org_unit_full_path(?,?)' if (@binds > 1);

	my $sth = actor::org_unit->db_Main->prepare_cached("SELECT * FROM $func");
	$sth->execute(@binds);

	$client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.full_path',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'org_unit_full_path',
);

sub org_unit_ancestors {
	my $self = shift;
	my $client = shift;
	my $id = shift;

	return undef unless ($id);

	my $func = 'actor.org_unit_ancestors(?)';

	my $sth = actor::org_unit->db_Main->prepare_cached(<<"	SQL");
		SELECT	f.*
		  FROM	$func f
			JOIN actor.org_unit_type t ON (f.ou_type = t.id)
		  ORDER BY t.depth, f.name;
	SQL
	$sth->execute(''.$id);

	$client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.ancestors',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'org_unit_ancestors',
);

sub org_unit_descendants {
	my $self = shift;
	my $client = shift;
	my $id = shift;
	my $depth = shift;

	return undef unless ($id);

	my $func = 'actor.org_unit_descendants(?)';
	if (defined $depth) {
		$func = 'actor.org_unit_descendants(?,?)';
	}

	my $sth = actor::org_unit->db_Main->prepare_cached("SELECT * FROM $func");
	$sth->execute(''.$id, ''.$depth) if (defined $depth);
	$sth->execute(''.$id) unless (defined $depth);

	$client->respond( $_->to_fieldmapper ) for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.descendants',
	api_level	=> 1,
	stream		=> 1,
	method		=> 'org_unit_descendants',
);

sub fleshed_actor_stat_cat {
        my $self = shift;
        my $client = shift;
        my @list = @_;
        
	@list = ($list[0]) unless ($self->api_name =~ /batch/o);

	for my $sc (@list) {
		my $cat = actor::stat_cat->retrieve($sc);
		next unless ($cat);

		my $sc_fm = $cat->to_fieldmapper;
		$sc_fm->entries( [ map { $_->to_fieldmapper } $cat->entries ] );

		$client->respond( $sc_fm );

	}

	return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.fleshed.actor.stat_cat.retrieve',
        api_level       => 1,
	argc		=> 1,
        method          => 'fleshed_actor_stat_cat',
);

__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.fleshed.actor.stat_cat.retrieve.batch',
        api_level       => 1,
	argc		=> 1,
        stream          => 1,
        method          => 'fleshed_actor_stat_cat',
);

#XXX Fix stored proc calls
sub ranged_actor_stat_cat_all {
        my $self = shift;
        my $client = shift;
        my $ou = ''.shift();
        
        return undef unless ($ou);
        my $s_table = actor::stat_cat->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
                        JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  ORDER BY name
        SQL

	$fleshed = 0;
	$fleshed = 1 if ($self->api_name =~ /fleshed/o);

        my $sth = actor::stat_cat->db_Main->prepare_cached($select);
        $sth->execute($ou);

        for my $sc ( map { actor::stat_cat->construct($_) } $sth->fetchall_hash ) {
		my $sc_fm = $sc->to_fieldmapper;
		$sc_fm->entries(
			[ $self->method_lookup( 'open-ils.storage.ranged.actor.stat_cat_entry.search.stat_cat' )->run($ou,$sc->id) ]
		) if ($fleshed);
		$client->respond( $sc_fm );
	}

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.fleshed.actor.stat_cat.all',
        api_level       => 1,
	argc		=> 1,
        stream          => 1,
        method          => 'ranged_actor_stat_cat_all',
);

__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.actor.stat_cat.all',
        api_level       => 1,
	argc		=> 1,
        stream          => 1,
        method          => 'ranged_actor_stat_cat_all',
);

#XXX Fix stored proc calls
sub ranged_actor_stat_cat_entry {
        my $self = shift;
        my $client = shift;
        my $ou = ''.shift();
        my $sc = ''.shift();
        
        return undef unless ($ou);
        my $s_table = actor::stat_cat_entry->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
                        JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	stat_cat = ?
		  ORDER BY name
        SQL

        my $sth = actor::stat_cat->db_Main->prepare_cached($select);
        $sth->execute($ou,$sc);

        for my $sce ( map { actor::stat_cat_entry->construct($_) } $sth->fetchall_hash ) {
		$client->respond( $sce->to_fieldmapper );
	}

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.actor.stat_cat_entry.search.stat_cat',
        api_level       => 1,
        stream          => 1,
        method          => 'ranged_actor_stat_cat_entry',
);


1;
