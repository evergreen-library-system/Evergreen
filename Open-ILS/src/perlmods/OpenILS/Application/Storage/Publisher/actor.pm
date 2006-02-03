package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::actor;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Utils::Fieldmapper;

my $log = 'OpenSRF::Utils::Logger';

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


sub patron_search {
	my $self = shift;
	my $client = shift;
	my $search = shift;

	# group 0 = user
	# group 1 = address
	# group 2 = phone, ident

	my $usr = join ' AND ', map { "LOWER($_) ~ ?" } grep { ''.$$search{$_}{group} eq '0' } keys %$search;
	my @usrv = map { "^$$search{$_}{value}" } grep { ''.$$search{$_}{group} eq '0' } keys %$search;

	my $addr = join ' AND ', map { "LOWER($_) ~ ?" } grep { ''.$$search{$_}{group} eq '1' } keys %$search;
	my @addrv = map { "^$$search{$_}{value}" } grep { ''.$$search{$_}{group} eq '1' } keys %$search;

	my $pv = $$search{phone}{value};
	my $iv = $$search{ident}{value};

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
	if ($pv) {
		for my $i ( qw/ident_value ident_value2/ ) {
			push @is, "LOWER($i) ~ ?";
			push @identv, "^$iv";
		}
		$ident = '(' . join(' OR ', @is) . ')';
	}

	my $usr_where = join ' AND ', grep { $_ } ($usr,$phone,$ident);
	my $addr_where = $addr;


	my $u_table = actor::user->table;
	my $a_table = actor::user_address->table;

	my $u_select = "SELECT id FROM $u_table a WHERE $usr_where";
	my $a_select = "SELECT usr FROM $a_table a WHERE $addr_where";

	my $select = '';
	if ($usr_where) {
		if ($addr_where) {
			$select = "$u_select INTERSECT $a_select";
		} else {
			$select = $u_select;
		}
	} elsif ($addr_where) {
		$select = $a_select;
	} else {
		return undef;
	}

	return actor::user->db_Main->selectcol_arrayref($select." LIMIT 1000", {}, map {lc($_)} (@usrv,@phonev,@identv,@addrv));
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

sub profile_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( actor::profile->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'profile_all',
	api_name	=> 'open-ils.storage.direct.actor.profile.retrieve.all',
	argc            => 0,
	stream          => 1,
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
