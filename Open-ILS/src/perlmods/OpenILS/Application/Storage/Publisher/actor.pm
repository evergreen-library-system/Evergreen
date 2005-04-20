package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
#use OpenILS::Application::Storage::CDBI::actor;
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

	my @fms;
	push @fms, $_->to_fieldmapper for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return \@fms;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.org_unit.retrieve.all',
	api_level	=> 1,
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

	my @fms;
	push @fms, $_->to_fieldmapper for ( map { actor::org_unit_type->construct($_) } $sth->fetchall_hash );

	return \@fms;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.org_unit_type.retrieve.all',
	api_level	=> 1,
	method		=> 'org_unit_type_list',
);

sub org_unit_descendants {
	my $self = shift;
	my $client = shift;
	my $id = shift;

	return undef unless ($id);

	my $select =<<"	SQL";
	SELECT	a.*
	  FROM	connectby('actor.org_unit','id','parent_ou','name',?,'100','.')
	  		as t(keyid text, parent_keyid text, level int, branch text,pos int),
		actor.org_unit a
	  WHERE	t.keyid = a.id
	  ORDER BY t.pos;
	SQL

	my $sth = actor::org_unit->db_Main->prepare_cached($select);
	$sth->execute($id);

	my @fms;
	push @fms, $_->to_fieldmapper for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return \@fms;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.descendants',
	api_level	=> 1,
	method		=> 'org_unit_descendants',
);


1;
