package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::actor;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Utils::Fieldmapper;

my $log = 'OpenSRF::Utils::Logger';

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
	api_name	=> 'open-ils.storage.actor.org_unit_list',
	api_level	=> 1,
	method		=> 'org_unit_list',
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
	api_name	=> 'open-ils.storage.actor.org_unit_descendants',
	api_level	=> 1,
	method		=> 'org_unit_descendants',
);


sub get_user_record {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	my $search_field = 'id';
	$search_field = 'usrname' if ($self->api_name =~/userid/o);
	$search_field = 'usrname' if ($self->api_name =~/username/o);

	for my $id ( @ids ) {
		next unless ($id);
		
		$log->debug("Searching for $id using ".$self->api_name, DEBUG);

		my ($rec) = actor::user->fast_fieldmapper($search_field => "$id");
		$client->respond( $rec ) if ($rec);

		last if ($self->api_name !~ /list$/o);
	}
	return undef;
}
#__PACKAGE__->register_method(
	#method		=> 'get_user_record',
	#api_name	=> 'open-ils.storage.actor.user.retrieve',
	#api_level	=> 1,
	#argc		=> 1,
#);
#__PACKAGE__->register_method(
	#method		=> 'get_user_record',
	#api_name	=> 'open-ils.storage.actor.user.search.username',
	#api_level	=> 1,
	#argc		=> 1,
#);
#__PACKAGE__->register_method(
	#method		=> 'get_user_record',
	#api_name	=> 'open-ils.storage.actor.user.search.userid',
	#api_level	=> 1,
	#argc		=> 1,
#);
#__PACKAGE__->register_method(
	#method		=> 'get_user_record',
	#api_name	=> 'open-ils.storage.actor.user.retrieve.list',
	#api_level	=> 1,
	#argc		=> 1,
#);
#__PACKAGE__->register_method(
	#method		=> 'get_user_record',
	#api_name	=> 'open-ils.storage.actor.user.search.username.list',
	#api_level	=> 1,
	#stream		=> 1,
	#argc		=> 1,
#);
#__PACKAGE__->register_method(
	#method		=> 'get_user_record',
	#api_name	=> 'open-ils.storage.actor.user.search.userid.list',
	#api_level	=> 1,
	#stream		=> 1,
	#argc		=> 1,
#);

sub update_user_record {
        my $self = shift;
        my $client = shift;
        my $user = shift;

        my $rec = actor::user->update($user);
        return 0 unless ($rec);
        return 1;
}
#__PACKAGE__->register_method(
        #method          => 'update_user_record',
        #api_name        => 'open-ils.storage.actor.user.update',
        #api_level       => 1,
        #argc            => 1,
#);

sub delete_record_entry {
        my $self = shift;
        my $client = shift;
        my $user = shift;

        my $rec = actor::user->delete($user);
	return 0 unless ($rec);
        return 1;
}
#__PACKAGE__->register_method(
        #method          => 'delete_user_record',
        #api_name        => 'open-ils.storage.actor.user.delete',
        #api_level       => 1,
        #argc            => 1,
#);

1;
