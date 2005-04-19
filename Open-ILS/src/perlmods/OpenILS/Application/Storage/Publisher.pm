package OpenILS::Application::Storage::Publisher;
use base qw/OpenILS::Application::Storage/;
our $VERSION = 1;

use Digest::MD5 qw/md5_hex/;
use OpenSRF::EX qw/:try/;;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Utils::Fieldmapper;

my $log = 'OpenSRF::Utils::Logger';


sub register_method {
	my $class = shift;
	my %args = @_;
	my %dup_args = %args;

	$class = ref($class) || $class;

	$args{package} ||= $class;
	__PACKAGE__->SUPER::register_method( %args );

	if (exists($dup_args{cachable}) and $dup_args{cachable}) {
		(my $name = $dup_args{api_name}) =~ s/^open-ils\.storage/open-ils.storage.cachable/o;
		if ($name ne $dup_args{api_name}) {
			$dup_args{real_api_name} = $dup_args{api_name};
			$dup_args{method} = 'cachable_wrapper';
			$dup_args{api_name} = $name;
			$dup_args{package} = __PACKAGE__;
			__PACKAGE__->SUPER::register_method( %dup_args );
		}
	}
}

sub cachable_wrapper {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my %cache_args = (
		limit	=> 100,
		offset	=> 0,
		timeout	=> 300,
	);

	my @real_args;
	my $key_string = $self->api_name;
	for (my $ind = 0; $ind < scalar(@args); $ind++) {
		if (	"$args[$ind]" eq 'limit' ||
			"$args[$ind]" eq 'offset' ||
			"$args[$ind]" eq 'timeout' ) {

			my $key_ind = $ind;
			$ind++;
			my $value_ind = $ind;
			$cache_args{$args[$key_ind]} = $args[$value_ind];
			$log->debug("Cache limiter value for $args[$key_ind] is $args[$value_ind]", INTERNAL);
			next;
		}
		$key_string .= $args[$ind];
		$log->debug("Partial cache key value is $args[$ind]", INTERNAL);
		push @real_args, $args[$ind];
	}

	my $cache_key = md5_hex($key_string);
	$log->debug("Key string for cache lookup is $key_string -> $cache_key", DEBUG);

	my $cached_res = OpenSRF::Utils::Cache->new->get_cache( $cache_key );
	if (defined $cached_res) {
		$log->debug("Found ".scalar(@$cached_res)." records in the cache", INFO);
		$log->debug("Values from cache: ".join(', ', @$cached_res), INTERNAL);
        	$client->respond( $_ ) for ( grep { defined } @$cached_res[$cache_args{offset} .. int($cache_args{offset} + $cache_args{limit} - 1)] );
		return undef;
	}

	my $method = $self->method_lookup($self->{real_api_name});
	my @res = $method->run(@real_args);


        $client->respond( $_ ) for ( grep { defined } @res[$cache_args{offset} .. int($cache_args{offset} + $cache_args{limit} - 1)] );

        OpenSRF::Utils::Cache->new->put_cache( $cache_key => \@res => $cache_args{timeout});

	return undef;
}

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

eval '
use OpenILS::Application::Storage::Publisher::actor;
use OpenILS::Application::Storage::Publisher::action;
use OpenILS::Application::Storage::Publisher::asset;
use OpenILS::Application::Storage::Publisher::biblio;
use OpenILS::Application::Storage::Publisher::config;
use OpenILS::Application::Storage::Publisher::metabib;
';

for my $fmclass ( (Fieldmapper->classes) ) {
	$log->debug("Generating methods for Fieldmapper class $fmclass", DEBUG);

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
			cachable	=> 1,
		);
	}

	# Create the retrieve method
	unless ( __PACKAGE__->is_registered( $api_prefix.'.retrieve' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.retrieve',
			method		=> 'retrieve_node',
			api_level	=> 1,
			cdbi		=> $cdbi,
			cachable	=> 1,
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
			cachable	=> 1,
		);
	}

	unless ($fmclass->is_virtual) {
		for my $field ($fmclass->real_fields) {
			unless ( __PACKAGE__->is_registered( $api_prefix.'.search.'.$field ) ) {
				__PACKAGE__->register_method(
					api_name	=> $api_prefix.'.search.'.$field,
					method		=> 'search_one_field',
					api_level	=> 1,
					cdbi		=> $cdbi,
					cachable	=> 1,
				);
			}
			unless ( __PACKAGE__->is_registered( $api_prefix.'.search_like.'.$field ) ) {
				__PACKAGE__->register_method(
					api_name	=> $api_prefix.'.search_like.'.$field,
					method		=> 'search_one_field',
					api_level	=> 1,
					cdbi		=> $cdbi,
					cachable	=> 1,
				);
			}
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
