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

		($rec) = actor::user->search( usrname => $id) if ($self->api_name =~/username/o);
		($rec) = actor::user->search( usrid => $id) if ($self->api_name =~/userid/o);

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
	api_name	=> 'open-ils.storage.actor.user.retrieve.username',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.retrieve.userid',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.retrieve.username.list',
	api_level	=> 1,
	stream		=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_user_record',
	api_name	=> 'open-ils.storage.actor.user.retrieve.userid.list',
	api_level	=> 1,
	stream		=> 1,
	argc		=> 1,
);

1;
