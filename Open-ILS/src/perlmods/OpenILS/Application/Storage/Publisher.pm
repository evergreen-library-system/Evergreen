package OpenILS::Application::Storage::Publisher;
use base qw/OpenILS::Application::Storage/;
our $VERSION = 1;

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


for my $fmclass ( Fieldmapper->classes ) {
	(my $cdbi = $fmclass) =~ s/^Fieldmapper:://o;
	(my $class = $cdbi) =~ s/::.*//o;
	(my $api_class = $cdbi) =~ s/::/./go;
	my $registration_class = __PACKAGE__ . "::$class";
	my $api_prefix = 'open-ils.storage.'.$api_class;

	warn "\tfmclass => $fmclass\n\tclass => $class\n\tregclass => $registration_class\n\tprefix => $api_prefix\n\tcdbi => $cdbi\n\n";

	# Create the create method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.create' ) ) {
		*{ $registration_class . '::create_node' } = sub {
			my $self = shift;
			my $client = shift;
			my $node = shift;

			my $success;
			try {
				my $rec = $cdbi->create($node);
				$success = $rec->id;
			} catch Error with {
				$success = 0;
			};

			return $success;
		};
		$registration_class->register_method(
			api_name	=> $api_prefix.'.create',
			method		=> 'create_node',
			api_level	=> 1,
		);
	}

	# Create the batch create method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.batch.create' ) ) {
		*{ $registration_class . '::create_node_batch' } = sub {
			my $self = shift;
			my $client = shift;
			my @nodes = @_;

			my $method = $self->method_lookup($api_prefix.'.create');

			my @success;
			while ( my $node = shift(@nodes) ) {
				my ($res) = $method->run( $node ); 
					push(@success, 1) if ($res >= 0);
			}

			my $insert_total = 0;
			$insert_total += $_ for (@success);

			return $insert_total;
		};
		$registration_class->register_method(
			api_name	=> $api_prefix.'.batch.create',
			method		=> 'create_node_batch',
			api_level	=> 1,
		);
	}

	# Create the update method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.update' ) ) {
		*{ $registration_class . '::update_node' } = sub {
			my $self = shift;
			my $client = shift;
			my $node = shift;

			return $cdbi->update($node);
		};
		$registration_class->register_method(
			api_name	=> $api_prefix.'.update',
			method		=> 'update_node',
			api_level	=> 1,
		);
	}

	# Create the batch update method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.batch.update' ) ) {
		*{ $registration_class . '::update_node_batch' } = sub {
			my $self = shift;
			my $client = shift;
			my @nodes = @_;

			my $method = $self->method_lookup($api_prefix.'.update');

			my @success;
			while ( my $node = shift(@nodes) ) {
				my ($res) = $method->run( $node ); 
					push(@success, $res) if ($res >= 0);
			}

			my $insert_total = 0;
			$insert_total += $_ for (@success);

			return $insert_total;
		};
		$registration_class->register_method(
			api_name	=> $api_prefix.'.batch.update',
			method		=> 'update_node_batch',
			api_level	=> 1,
		);
	}

}

1;
