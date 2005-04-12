package OpenILS::Application::Storage::Publisher;
use base qw/OpenILS::Application::Storage/;
our $VERSION = 1;

use OpenSRF::EX qw/:try/;;
use OpenSRF::Utils::Logger;
my $log = 'OpenSRF::Utils::Logger';

use OpenILS::Utils::Fieldmapper;
#use OpenILS::Application::Storage::CDBI;

#use OpenILS::Application::Storage::CDBI::actor;
#use OpenILS::Application::Storage::CDBI::asset;
#use OpenILS::Application::Storage::CDBI::biblio;
#use OpenILS::Application::Storage::CDBI::config;
#use OpenILS::Application::Storage::CDBI::metabib;

use OpenILS::Application::Storage::Publisher::actor;
use OpenILS::Application::Storage::Publisher::action;
use OpenILS::Application::Storage::Publisher::asset;
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

		last if ($self->api_name !~ /batch/o);
	}
	return undef;
}

sub search {
	my $self = shift;
	my $client = shift;
	my $searches = shift;

	my $cdbi = $self->{cdbi};

	$log->debug("Searching $cdbi for { ".join(',', map { "$_ => $$searches{$_}" } keys %$searches).' }',DEBUG);

	for my $obj ($cdbi->search($searches)) {
		$client->respond( $obj->to_fieldmapper );
	}
	return undef;
}

sub search_one_field {
	my $self = shift;
	my $client = shift;
	my @terms = @_;

	(my $search_type = $self->api_name) =~ s/.*\.(search[^.]*).*/$1/o;
	(my $col = $self->api_name) =~ s/.*\.$search_type\.([^.]+).*/$1/;
	my $cdbi = $self->{cdbi};

	my $like = 0;
	$like = 1 if ($search_type =~ /like$/o);

	for my $term (@terms) {
		$log->debug("Searching $cdbi for $col using type $search_type, value '$term'",DEBUG);
		$client->respond( [ $cdbi->fast_fieldmapper($term,$col,$like) ] );
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

sub mass_delete {
	my $self = shift;
	my $client = shift;
	my $search = shift;

	my $where = 'WHERE ';

	my $cdbi = $self->{cdbi};
	my $table = $cdbi->table;

	my @keys = sort keys %$search;
	
	my @binds;
	my @wheres;
	for my $col ( @keys ) {
		if (ref($$search{$col}) and ref($$search{$col}) =~ /ARRAY/o) {
			push @wheres, "$col IN (" . join(',', map { '?' } @{ $$search{$col} }) . ')';
			push @binds, map { "$_" } @{ $$search{$col} };
		} else {
			push @wheres, "$col = ?";
			push @binds, $$search{$col};
		}
	}
	$where .= join ' AND ', @wheres;

	my $delete = "DELETE FROM $table $where";

	$log->debug("Performing MASS deletion : $delete",DEBUG);

	my $dbh = $cdbi->db_Main;
	my $success = 1;
	try {
		my $sth = $dbh->prepare($delete);
		$sth->execute( @binds );
		$sth->finish;
		$log->debug("MASS Delete succeeded",DEBUG);
	} catch Error with {
		$log->debug("MASS Delete FAILED : ".shift(),DEBUG);
		$success = 0;
	};
	return $success;
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
	my $api_prefix = 'open-ils.storage.direct.'.$api_class;

	# Create the search method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.search' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.search',
			method		=> 'search',
			api_level	=> 1,
			stream		=> 1,
			cdbi		=> $cdbi,
		);
	}

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
			method		=> 'retrieve_node',
			api_level	=> 1,
			stream		=> 1,
			cdbi		=> $cdbi,
		);
	}

	for my $field ($fmclass->real_fields) {
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search.'.$field ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search.'.$field,
				method		=> 'search_one_field',
				api_level	=> 1,
				cdbi		=> $cdbi,
			);
		}
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search_like.'.$field ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search_like.'.$field,
				method		=> 'search_one_field',
				api_level	=> 1,
				cdbi		=> $cdbi,
			);
		}
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

	# Create the search-based mass delete method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.mass_delete' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.mass_delete',
			method		=> 'mass_delete',
			api_level	=> 1,
			cdbi		=> $cdbi,
		);
	}

}

1;
