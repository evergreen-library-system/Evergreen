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

	for my $id ( @ids ) {
		next unless ($id);
		
		$log->debug("Searching for $id using ".$self->api_name, DEBUG);

		my $rec;

		if ($self->api_name =~/username/o) {
			($rec) = actor::user->search( usrname => "$id");
		} elsif ($self->api_name =~/userid/o) {
			($rec) = actor::user->search( usrid => "$id");
		} else {
			$rec = actor::user->retrieve("$id");
		}

		if ($rec) {

			my $user = Fieldmapper::actor::user->new;

			for my $field (Fieldmapper::actor::user->real_fields) {
				$user->$field($rec->$field);
			}

			$client->respond( $user );

		}

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

        my $rec = actor::user->retrieve(''.$user->id);
        return 0 unless ($rec);

        $rec->autoupdate(0);

        for my $field ( Fieldmapper::actor::user->real_fields ) {
                $rec->$field( $user->$field );
        }

        return 0 unless ($rec->is_changed);

        $rec->update;

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

        my $rec = actor::user->retrieve(''.$user->id);
        return 0 unless ($rec);

        $rec->delete;
        return 1;
}
__PACKAGE__->register_method(
        method          => 'delete_user_record',
        api_name        => 'open-ils.storage.actor.user.delete',
        api_level       => 1,
        argc            => 1,
);

1;
