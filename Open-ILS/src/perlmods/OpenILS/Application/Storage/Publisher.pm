package OpenILS::Application::Storage::Publisher;
use base qw/OpenILS::Application::Storage/;
our $VERSION = 1;

use Digest::MD5 qw/md5_hex/;
use OpenSRF::EX qw/:try/;;
use OpenSRF::Utils;
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
		limit		=> 100,
		offset		=> 0,
		timeout		=> 7200,
		cache_page_size	=> 1000,
	);

	my @real_args;
	my $key_string = $self->api_name;
	for (my $ind = 0; $ind < scalar(@args); $ind++) {
		if (	$args[$ind] eq 'limit' ||
			$args[$ind] eq 'offset' ||
			$args[$ind] eq 'cache_page_size' ||
			$args[$ind] eq 'timeout' ) {

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

	my $cache_page = int($cache_args{offset} / $cache_args{cache_page_size});
	my $cache_key;
	{	use bytes;
		$cache_key = md5_hex($key_string.$cache_page);
	}

	$log->debug("Key string for cache lookup is $key_string -> $cache_key", DEBUG);
	$log->debug("Cache page is $cache_page", DEBUG);

	my $cached_res = OpenSRF::Utils::Cache->new->get_cache( $cache_key );
	if (defined $cached_res) {
		$log->debug("Found ".scalar(@$cached_res)." records in the cache", INFO);
		$log->debug("Values from cache: ".join(', ', @$cached_res), INTERNAL);
		my $start = int($cache_args{offset} - ($cache_page * $cache_args{cache_page_size}));
		my $end = int($start + $cache_args{limit} - 1);
		$log->debug("Responding with values from ".$start.' to '.$end,DEBUG);
        	$client->respond( $_ ) for ( grep { defined } @$cached_res[ $start .. $end ]);
		return undef;
	}

	my $method = $self->method_lookup($self->{real_api_name});
	my @res = $method->run(@real_args);


        $client->respond( $_ ) for ( grep { defined } @res[$cache_args{offset} .. int($cache_args{offset} + $cache_args{limit} - 1)] );

	$log->debug("Saving values from ".int($cache_page * $cache_args{cache_page_size})." to ".
		int(($cache_page + 1) * $cache_args{cache_page_size}). "to the cache", INTERNAL);
	try {
		OpenSRF::Utils::Cache->new->put_cache(
			$cache_key =>
			[@res[int($cache_page * $cache_args{cache_page_size}) .. int(($cache_page + 1) * $cache_args{cache_page_size}) ]] =>
			OpenSRF::Utils->interval_to_seconds( $cache_args{timeout} )
		);
	} catch Error with {
		my $e = shift;
		$log->error("Cache seems to be down, $e");
	};

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
		if ($self->api_name !~ /batch/o) {
			return $rec if ($rec);
		}
		$client->respond($rec);
	}
	return undef;
}

sub search_where {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my $cdbi = $self->{cdbi};

	for my $obj ($cdbi->search_where(@args)) {
		next unless ref($obj);
		$client->respond( $obj->to_fieldmapper );
	}
	return undef;
}

sub search {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	my $cdbi = $self->{cdbi};

	(my $search_type = $self->api_name) =~ s/.*\.(search[^.]*).*/$1/o;

	for my $obj ($cdbi->$search_type(@args)) {
		next unless ref($obj);
		$client->respond( $obj->to_fieldmapper );
	}
	return undef;
}

sub search_one_field {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	(my $field = $self->api_name) =~ s/.*\.([^\.]+)$/$1/o;

	return search( $self, $client, $field, @args );
}

sub old_search_one_field {
	my $self = shift;
	my $client = shift;
	my @terms = @_;

	(my $search_type = $self->api_name) =~ s/.*\.(search[^.]*).*/$1/o;
	(my $col = $self->api_name) =~ s/.*\.$search_type\.([^.]+).*/$1/;
	my $cdbi = $self->{cdbi};

	my $like = 0;
	$like = 1 if ($search_type =~ /like$/o);
	$like = 2 if ($search_type =~ /fts$/o);
	$like = 3 if ($search_type =~ /regex$/o);

	for my $term (@terms) {
		$log->debug("Searching $cdbi for $col using type $search_type, value '$term'",DEBUG);
		if (@terms == 1) {
			return [ $cdbi->fast_fieldmapper($term,$col,$like) ];
		}
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
use OpenILS::Application::Storage::Publisher::money;
use OpenILS::Application::Storage::Publisher::permission;
';

for my $fmclass ( (Fieldmapper->classes) ) {

	next if ($fmclass->is_virtual);

	$log->debug("Generating methods for Fieldmapper class $fmclass", DEBUG);

	(my $cdbi = $fmclass) =~ s/^Fieldmapper:://o;
	(my $class = $cdbi) =~ s/::.*//o;
	(my $api_class = $cdbi) =~ s/::/./go;
	my $registration_class = __PACKAGE__ . "::$class";
	my $api_prefix = 'open-ils.storage.direct.'.$api_class;

	# Create the search methods
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

	unless ( __PACKAGE__->is_registered( $api_prefix.'.search_where' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.search_where',
			method		=> 'search_where',
			api_level	=> 1,
			stream		=> 1,
			cdbi		=> $cdbi,
			cachable	=> 1,
		);
	}

	unless ( __PACKAGE__->is_registered( $api_prefix.'.search_like' ) ) {
		__PACKAGE__->register_method(
			api_name	=> $api_prefix.'.search_like',
			method		=> 'search',
			api_level	=> 1,
			stream		=> 1,
			cdbi		=> $cdbi,
			cachable	=> 1,
		);
	}

	if (\&Class::DBI::search_fts) {
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search_fts' ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search_fts',
				method		=> 'search',
				api_level	=> 1,
				stream		=> 1,
				cdbi		=> $cdbi,
				cachable	=> 1,
			);
		}
	}

	if (\&Class::DBI::search_regex) {
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search_regex' ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search_regex',
				method		=> 'search',
				api_level	=> 1,
				stream		=> 1,
				cdbi		=> $cdbi,
				cachable	=> 1,
			);
		}
	}

	if (\&Class::DBI::search_ilike) {
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search_ilike' ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search_ilike',
				method		=> 'search',
				api_level	=> 1,
				stream		=> 1,
				cdbi		=> $cdbi,
				cachable	=> 1,
			);
		}
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

	for my $field ($fmclass->real_fields) {
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search.'.$field ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search.'.$field,
				method		=> 'search_one_field',
				api_level	=> 1,
				cdbi		=> $cdbi,
				cachable	=> 1,
				stream		=> 1,
			);
		}
		unless ( __PACKAGE__->is_registered( $api_prefix.'.search_like.'.$field ) ) {
			__PACKAGE__->register_method(
				api_name	=> $api_prefix.'.search_like.'.$field,
				method		=> 'search_one_field',
				api_level	=> 1,
				cdbi		=> $cdbi,
				cachable	=> 1,
				stream		=> 1,
			);
		}
		if (\&Class::DBI::search_fts) {
			unless ( __PACKAGE__->is_registered( $api_prefix.'.search_fts.'.$field ) ) {
				__PACKAGE__->register_method(
					api_name	=> $api_prefix.'.search_fts.'.$field,
					method		=> 'search_one_field',
					api_level	=> 1,
					cdbi		=> $cdbi,
					cachable	=> 1,
					stream		=> 1,
				);
			}
		}
		if (\&Class::DBI::search_regex) {
			unless ( __PACKAGE__->is_registered( $api_prefix.'.search_regex.'.$field ) ) {
				__PACKAGE__->register_method(
					api_name	=> $api_prefix.'.search_regex.'.$field,
					method		=> 'search_one_field',
					api_level	=> 1,
					cdbi		=> $cdbi,
					cachable	=> 1,
					stream		=> 1,
				);
			}
		}
		if (\&Class::DBI::search_ilike) {
			unless ( __PACKAGE__->is_registered( $api_prefix.'.search_ilike.'.$field ) ) {
				__PACKAGE__->register_method(
					api_name	=> $api_prefix.'.search_ilike.'.$field,
					method		=> 'search_one_field',
					api_level	=> 1,
					cdbi		=> $cdbi,
					cachable	=> 1,
					stream		=> 1,
				);
			}
		}
	}


	unless ($fmclass->is_readonly) {
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
}

1;
