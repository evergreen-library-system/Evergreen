package OpenILS::Application::Storage::CDBI;
use base qw/Class::DBI/;
use Class::DBI;


our $VERSION = 1;


use OpenILS::Application::Storage::CDBI::config;
use OpenILS::Application::Storage::CDBI::actor;
use OpenILS::Application::Storage::CDBI::asset;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Application::Storage::CDBI::metabib;

use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger;

my $log = 'OpenSRF::Utils::Logger';

sub child_init {
	my $self = shift;

	__PACKAGE__->set_sql( 'OILSFastSearch', <<"	SQL", 'Main');
		SELECT	%s
		  FROM	%s
		  WHERE	%s = ?
	SQL

	__PACKAGE__->set_sql( 'OILSFastOrderedSearch', <<"	SQL", 'Main');
		SELECT	%s
		  FROM	%s
		  WHERE	%s = ?
		  ORDER BY %s
	SQL

	$self->SUPER::child_init(@_);

}

sub fast_flesh_sth {
	my $class = shift;
	$class = ref($class) || $class;

	my $field = shift;
	my $value = shift;
	my $order = shift;

	if (!(defined($order) and ref($order) and ref($order) eq 'HASH')) {
		if (defined($value) and ref($order) and ref($order) eq 'HASH') {
			$order = $value;
			$value = $field;
			$field = $class->primary_column;
		} else {
			$order = { order_by => 'id' }
		}
	}

	unless (defined $value) {
		$value = $field;
		$field = $class->primary_column;
	}

	my $fm_class = 'Fieldmapper::'.$class;
	my $field_list = join ',', $class->columns('All');
	
	my $sth = $class->sql_OILSFastOrderedSearch( $field_list, $class->table, $field, $order->{order_by});
	$sth->execute($value);
	return $sth;
}

sub fast_flesh {
	my $self = shift;
	return map $class->construct($_), $self->fast_flesh_sth(@_)->fetchall_hash;
}

sub fast_fieldmapper {
	my $self = shift;
	my $class = ref($self) || $self;
	my $fm_class = 'Fieldmapper::'.$class;
	my @fms;
	for my $hash ($self->fast_flesh_sth(@_)->fetchall_hash) {
		my $fm = $fm_class->new;
		for my $field ( keys %$hash ) {
			$fm->$field( $$hash{$field} );
		}
		push @fms, $fm;
	}
	return @fms;
}

sub retrieve {
	my $self = shift;
	my $arg = shift;
	if (ref($arg) and UNIVERSAL::isa($arg => 'Fieldmapper')) {
		$arg = $arg->id;
	}
	$log->debug("Retrieving $self with $arg", INTERNAL);
	my $rec =  $self->SUPER::retrieve("$arg");
	unless ($rec) {
		$log->debug("Could not retrieve $self with $arg!", DEBUG);
		return undef;
	}
	return $rec;
}

sub to_fieldmapper {
	my $obj = shift;
	my $class = ref($obj) || $obj;

	my $fm_class = 'Fieldmapper::'.$class;
	my $fm = $fm_class->new;

	if (ref($obj)) {
		for my $field ( $fm->real_fields ) {
			$fm->$field( $obj->$field );
		}
	}

	return $fm;
}

sub create {
	my $self = shift;
	my $arg = shift;

	if (ref($arg) and UNIVERSAL::isa($arg => 'Fieldmapper')) {
		return $self->create_from_fieldmapper($arg,@_);
	}

	return $self->SUPER::create($arg,@_);
}

sub create_from_fieldmapper {
	my $obj = shift;
	my $fm = shift;
	my @params = @_;

	my $class = ref($obj) || $obj;

	if (ref $fm) {
		my %hash = map { defined $fm->$_ ?
					($_ => $fm->$_) :
					()
				} $fm->real_fields;

		if ($class->find_column( 'last_xact_id' )) {
			my $xact_id = $class->current_xact_id;
			throw Error unless ($xact_id);
			$hash{last_xact_id} = $xact_id;
		}

		return $class->create( \%hash, @params );
	} else {
		return undef;
	}
}

sub delete {
	my $self = shift;
	my $arg = shift;

	if (ref($arg) and UNIVERSAL::isa($arg => 'Fieldmapper')) {
		$self = $self->retrieve($arg);
	}

	if ($class->find_column( 'last_xact_id' )) {
		my $xact_id = $self->current_xact_id;
		throw Error unless ($xact_id);
		$self->last_xact_id( $self->current_xact_id );
		$self->update;
	}

	$self->SUPER::delete;
	return $arg;
}

sub update {
	my $self = shift;
	my $arg = shift;

	$log->debug("Attempting to update using $arg", DEBUG) if ($arg);

	if (ref($arg) and UNIVERSAL::isa($arg => 'Fieldmapper')) {
		$self = $self->modify_from_fieldmapper($arg);
		$log->debug("Modification of $self seems to have failed....", DEBUG);
		return undef unless (defined $self);
	}

	$log->debug("Calling Class::DBI->update on modified object $self", DEBUG);
	return $self->SUPER::update;
}

sub modify_from_fieldmapper {
	my $obj = shift;
	my $fm = shift;

	$log->debug("Modifying object using fieldmapper", DEBUG);

	my $class = ref($obj) || $obj;

	if (!ref($obj)) {
		$obj = $class->retrieve($fm);
		unless ($obj) {
			$log->debug("Rretrieve using $fm (".$fm->id.") failed!", ERROR);
			throw OpenSRF::EX::WARN ("No $class with id of ".$fm->id."!!");
		}

	}

	my %hash = map { defined $fm->$_ ?
				($_ => $fm->$_) :
				()
			} $fm->real_fields;

	my $au = $obj->autoupdate;
	$obj->autoupdate(0);
	
	for my $field ( keys %hash ) {
		$obj->$field( $hash{$field} ) if ($obj->$field ne $hash{$field});
		$log->debug("Setting field $field on $obj to $hash{$field}",INTERNAL);
	}

	if ($class->find_column( 'last_xact_id' ) and $obj->is_changed) {
		my $xact_id = $obj->current_xact_id;
		throw Error unless ($xact_id);
		$hash{last_xact_id} = $xact_id;
	} else {
		$obj->autoupdate($au)
	}

	return $obj;
}



sub import {
	#-------------------------------------------------------------------------------
	actor::user->has_a( home_ou => 'actor::org_unit' );
	#actor::org_unit->has_a( address => 'actor::address' );
	#-------------------------------------------------------------------------------
	actor::org_unit->has_many( users => 'actor::user' );
	actor::org_unit->has_a( parent_ou => 'actor::org_unit' );
	actor::org_unit->has_a( ou_type => 'actor::org_unit_type' );
	#actor::org_unit->has_a( address => 'actor::address' );
	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	asset::copy->has_a( call_number => 'asset::call_number' );
	#asset::copy->might_have( metadata => 'asset::copy_metadata' );
	#-------------------------------------------------------------------------------
	#asset::copy_metadata->might_have( copy => 'asset::copy' );
	asset::copy_metadata->has_a( circulating_location => 'actor::org_unit');
	asset::copy_metadata->has_a( hold_radius => 'actor::org_unit_type');
	#-------------------------------------------------------------------------------
	asset::call_number->has_a( record => 'biblio::record_entry' );
	asset::call_number->has_many( copies => 'asset::copy' );
	#-------------------------------------------------------------------------------
	

	#-------------------------------------------------------------------------------
	biblio::record_note->has_a( record => 'biblio::record_entry' );
	#-------------------------------------------------------------------------------
	biblio::record_entry->has_a( creator => 'actor::user' );
	biblio::record_entry->has_a( editor => 'actor::user' );
	biblio::record_entry->might_have( mods_entry => 'biblio::record_mods' => qw/mods/ );
	biblio::record_entry->has_many( notes => 'biblio::record_note' );
	biblio::record_entry->has_many( nodes => 'biblio::record_node', { order_by => 'intra_doc_id' } );
	biblio::record_entry->has_many( call_numbers => 'asset::call_number' );
	
	# should we have just one field entry per class for each record???? (xslt vs xpath)
	#biblio::record_entry->has_a( title_field_entries => 'metabib::title_field_entry' );
	#biblio::record_entry->has_a( author_field_entries => 'metabib::author_field_entry' );
	#biblio::record_entry->has_a( subject_field_entries => 'metabib::subject_field_entry' );
	#biblio::record_entry->has_a( keyword_field_entries => 'metabib::keyword_field_entry' );
	#-------------------------------------------------------------------------------
	biblio::record_node->has_a( owner_doc => 'biblio::record_entry' );
	#biblio::record_node->has_a(
	#	parent_node	=> 'biblio::record_node::subnode',
	#	inflate		=> sub { return biblio::record_node::subnode::_load(@_) }
	#);
	#-------------------------------------------------------------------------------
	
	#-------------------------------------------------------------------------------
	metabib::metarecord->has_a( master_record => 'biblio::record_entry' );
	metabib::metarecord->has_many( source_records => [ 'metabib::metarecord_source_map' => 'source_record'] );
	#-------------------------------------------------------------------------------
	metabib::title_field_entry->has_many( source_records => [ 'metabib::title_field_entry_source_map' => 'source_record'] );
	metabib::title_field_entry->has_a( field => 'config::metabib_field' );
	#-------------------------------------------------------------------------------
	metabib::author_field_entry->has_many( source_records => [ 'metabib::author_field_entry_source_map' => 'source_record'] );
	metabib::author_field_entry->has_a( field => 'config::metabib_field' );
	#-------------------------------------------------------------------------------
	metabib::subject_field_entry->has_many( source_records => [ 'metabib::title_field_entry_source_map' => 'source_record'] );
	metabib::subject_field_entry->has_a( field => 'config::metabib_field' );
	#-------------------------------------------------------------------------------
	metabib::keyword_field_entry->has_many( source_records => [ 'metabib::keyword_field_entry_source_map' => 'source_record'] );
	metabib::keyword_field_entry->has_a( field => 'config::metabib_field' );
	#-------------------------------------------------------------------------------
	metabib::metarecord_source_map->has_a( metarecord => 'metabib::metarecord' );
	metabib::metarecord_source_map->has_a( source_record => 'biblio::record_entry' );
	#-------------------------------------------------------------------------------


	# should we have just one field entry per class for each record???? (xslt vs xpath)
	metabib::title_field_entry_source_map->has_a( field_entry => 'metabib::title_field_entry' );
	metabib::title_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
	#-------------------------------------------------------------------------------
	metabib::subject_field_entry_source_map->has_a( field_entry => 'metabib::subject_field_entry' );
	metabib::subject_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
	#-------------------------------------------------------------------------------
	metabib::author_field_entry_source_map->has_a( field_entry => 'metabib::author_field_entry' );
	metabib::author_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
	#-------------------------------------------------------------------------------
	metabib::keyword_field_entry_source_map->has_a( field_entry => 'metabib::keyword_field_entry' );
	metabib::keyword_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
	#-------------------------------------------------------------------------------
}


1;
