package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::actor;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Utils::Fieldmapper;

my $log = 'OpenSRF::Utils::Logger';

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
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.retrieve',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.search.username',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.search.userid',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.retrieve.list',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.search.username.list',
	api_level	=> 1,
	stream		=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.search.userid.list',
	api_level	=> 1,
	stream		=> 1,
	argc		=> 1,
);

sub update_user_record {
        my $self = shift;
        my $client = shift;
        my $user = shift;

        my $rec = actor::user->update($user);
        return 0 unless ($rec);
        return 1;
}
__PACKAGE__->register_method(
        method          => 'update_user_record',
        api_name        => 'open-ils.storage.actor.user.update',
        api_level       => 1,
        argc            => 1,
);

sub delete_record_entry {
        my $self = shift;
        my $client = shift;
        my $user = shift;

        my $rec = actor::user->delete($user);
	return 0 unless ($rec);
        return 1;
}
__PACKAGE__->register_method(
        method          => 'delete_user_record',
        api_name        => 'open-ils.storage.actor.user.delete',
        api_level       => 1,
        argc            => 1,
);

1;
