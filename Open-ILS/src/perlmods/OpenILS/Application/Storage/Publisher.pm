package OpenILS::Application::Storage::Publisher;
use base qw/OpenILS::Application::Storage/;
our $VERSION = 1;

use OpenSRF::EX qw/:try/;;
use OpenSRF::Utils::Logger;
my $log = 'OpenSRF::Utils::Logger';

use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Storage::CDBI;

#use OpenILS::Application::Storage::CDBI::actor;
#use OpenILS::Application::Storage::CDBI::asset;
#use OpenILS::Application::Storage::CDBI::biblio;
#use OpenILS::Application::Storage::CDBI::config;
#use OpenILS::Application::Storage::CDBI::metabib;

use OpenILS::Application::Storage::Publisher::actor;
#use OpenILS::Application::Storage::Publisher::asset;
use OpenILS::Application::Storage::Publisher::biblio;
use OpenILS::Application::Storage::Publisher::config;
use OpenILS::Application::Storage::Publisher::metabib;

sub retrieve_node {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	my $cdbi = $self->{cdbi};

	for my $id ( @ids ) {
		next unless ($id);

		my ($rec) = $cdbi->fast_fieldmapper($id);
		$client->respond( $rec ) if ($rec);

		last if ($self->api_name !~ /list/o);
	}
	return undef;
}


sub create_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;

	my $cdbi = $self->{cdbi};

	my $success;
	try {
		my $rec = $cdbi->create($node);
		$success = $rec->id if ($rec);
	} catch Error with {
		$success = 0;
	};

	return $success;
}

sub update_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;

	my $cdbi = $self->{cdbi};

	return $cdbi->update($node);
}

sub delete_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;

	my $cdbi = $self->{cdbi};

	my $success = 1;
	try {
		$success = $cdbi->delete($node);
	} catch Error with {
		$success = 0;
	};
	return $success;
}

sub batch_call {
	my $self = shift;
	my $client = shift;
	my @nodes = @_;

	my $cdbi = $self->{cdbi};
	my $api_name = $self->api_name;
	(my $single_call_api_name = $api_name) =~ s/batch\.//o;

	$log->debug("Default $api_name looking up $single_call_api_name...",INTERNAL);
	my $method = $self->method_lookup($single_call_api_name);

	my @success;
	while ( my $node = shift(@nodes) ) {
		my ($res) = $method->run( $node ); 
		push(@success, 1) if ($res >= 0);
	}

	my $insert_total = 0;
	$insert_total += $_ for (@success);

	return $insert_total;
}

for my $fmclass ( Fieldmapper->classes ) {
	(my $cdbi = $fmclass) =~ s/^Fieldmapper:://o;
	(my $class = $cdbi) =~ s/::.*//o;
	(my $api_class = $cdbi) =~ s/::/./go;
	my $registration_class = __PACKAGE__ . "::$class";
	my $api_prefix = 'open-ils.storage.'.$api_class;

	# Create the retrieve method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.retrieve' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.retrieve',
			method		=> 'retrieve_node',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the batch retrieve method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.batch.retrieve' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.batch.retrieve',
			method		=> 'batch_call',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the create method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.create' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.create',
			method		=> 'create_node',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the batch create method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.batch.create' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.batch.create',
			method		=> 'batch_call',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the update method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.update' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.update',
			method		=> 'update_node',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the batch update method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.batch.update' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.batch.update',
			method		=> 'batch_call',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the delete method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.delete' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.delete',
			method		=> 'delete_node',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

	# Create the batch delete method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.batch.delete' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.batch.delete',
			method		=> 'batch_call',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

}

1;
