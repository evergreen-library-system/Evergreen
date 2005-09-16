package OpenILS::Application::Storage::CDBI;
use base qw/Class::DBI/;
use Class::DBI;
use Class::DBI::AbstractSearch;

use OpenILS::Application::Storage::CDBI::actor;
use OpenILS::Application::Storage::CDBI::action;
use OpenILS::Application::Storage::CDBI::asset;
use OpenILS::Application::Storage::CDBI::authority;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Application::Storage::CDBI::config;
use OpenILS::Application::Storage::CDBI::metabib;
use OpenILS::Application::Storage::CDBI::money;
use OpenILS::Application::Storage::CDBI::permission;

use OpenSRF::Utils::Logger;
use OpenSRF::EX qw/:try/;

our $VERSION = undef;
my $log = 'OpenSRF::Utils::Logger';

sub child_init {
	my $self = shift;

	$log->debug("Creating ImaDBI Querys", DEBUG);
	__PACKAGE__->set_sql( 'OILSFastSearch', <<"	SQL", 'Main');
		SELECT	%s
		  FROM	%s
		  WHERE	%s = ?
	SQL

	__PACKAGE__->set_sql( 'OILSFastOrderedSearchLike', <<"	SQL", 'Main');
		SELECT	%s
		  FROM	%s
		  WHERE	%s LIKE ?
		  ORDER BY %s
	SQL

	__PACKAGE__->set_sql( 'OILSFastOrderedSearch', <<"	SQL", 'Main');
		SELECT	%s
		  FROM	%s
		  WHERE	%s = ?
		  ORDER BY %s
	SQL

	$log->debug("Calling Driver child_init", DEBUG);
	$self->SUPER::child_init(@_);

}

sub fast_flesh_sth {
	my $class = shift;
	$class = ref($class) || $class;

	my $field = shift;
	my $value = shift;
	my $order = shift;
	my $like = shift;


	if (!(defined($order) and ref($order) and ref($order) eq 'HASH')) {
		if (defined($value) and ref($value) and ref($value) eq 'HASH') {
			$order = $value;
			$value = undef;
		} else {
			$order = { order_by => $class->columns('Primary') }
		}
	}

	unless (defined $value) {
		$value = $field;
		($field) = $class->columns('Primary');
	}

	unless (defined $field) {
		($field) = $class->columns('Primary');
	}

	unless ($order->{order_by}) {
		$order = { order_by => $class->columns('Primary') }
	}

	my $fm_class = 'Fieldmapper::'.$class;
	my $field_list = join ',', $class->columns('All');
	
	my $sth;
	if (!$like) {
		$sth = $class->sql_OILSFastOrderedSearch( $field_list, $class->table, $field, $order->{order_by});
	} else {
		$sth = $class->sql_OILSFastOrderedSearchLike( $field_list, $class->table, $field, $order->{order_by});
	}
	$sth->execute($value);
	return $sth;
}

sub fast_flesh {
	my $self = shift;
	return map $class->construct($_), $self->fast_flesh_sth(@_)->fetchall_hash;
}

sub fast_fieldmapper {
	my $self = shift;
	my $id = shift;
	my $col = shift;
	my $like = shift;
	my $options = shift;
	my $class = ref($self) || $self;
	my $fm_class = 'Fieldmapper::'.$class;
	my @fms;
	$log->debug("fast_fieldmapper() ==> Retrieving $fm_class", INTERNAL);
	if ($like < 2) {
		for my $hash ($self->fast_flesh_sth( $col, "$id", { order_by => $col }, $like )->fetchall_hash) {
			my $fm = $fm_class->new;
			for my $field ( $fm_class->real_fields ) {
				$fm->$field( $$hash{$field} );
			}
			push @fms, $fm;
		}
	} else {
		my $search_type = 'search';
		if ($like == 2) {
			$search_type = 'search_fts'
		} elsif ($like == 3) {
			$search_type = 'search_regex'
		}

		for my $obj ($class->$search_type({ $col => $id}, $options)) {
			push @fms, $obj->to_fieldmapper;
		}
	}
	return @fms;
}

sub retrieve {
	my $self = shift;
	my $arg = shift;
	if (ref($arg) and UNIVERSAL::isa($arg => 'Fieldmapper')) {
		my ($col) = $self->primary_column;
		$log->debug("Using field $col as the primary key", INTERNAL);
		$arg = $arg->$col;
	}
	$log->debug("Retrieving $self with $arg", INTERNAL);
	my $rec;
	try {
		$rec = $self->SUPER::retrieve("$arg");
	} catch Error with {
		$log->debug("Could not retrieve $self with $arg! -- ".shift(), DEBUG);
		return undef;
	};
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

sub merge {
	my $self = shift;
	my $search = shift;
	my $arg = shift;

	delete $$arg{$_} for (keys %$search);

	my @objs = ($self);
	@objs = $self->search_where($search) unless (ref $self);

	if (@objs == 1) {
		return $objs[0]->update($arg);
	} elsif (@objs == 0) {
		return $self->create({%$search,%$arg});
	} else {
		throw OpenSRF::EX::WARN ("Non-unique search key for merge.  Perhaps you meant to use remote_update?");
	}
}

sub remote_update {
	my $self = shift;
	my $search = shift;
	my $arg = shift;

	delete $$arg{$_} for (keys %$search);

	my @objs = $self->search_where($search);
	if (@objs == 0) {
		throw OpenSRF::EX::WARN ("No objects found for remote_update.  Perhaps you meant to use merge?");
	} else {
		$_->update($arg) for (@objs);
		return scalar(@objs);
	}
}

sub create {
	my $self = shift;
	my $arg = shift;

	$log->debug("\$arg is $arg (".ref($arg).")",DEBUG);

	if (ref($arg) && UNIVERSAL::isa($arg => 'Fieldmapper')) {
		return $self->create_from_fieldmapper($arg,@_);
	}

	return $self->SUPER::create($arg,@_);
}

sub create_from_fieldmapper {
	my $obj = shift;
	my $fm = shift;
	my @params = @_;

	$log->debug("Creating node of type ".ref($fm), DEBUG);

	my $class = ref($obj) || $obj;
	my ($primary) = $class->columns('Primary');

	if (ref($fm) &&UNIVERSAL::isa($fm => 'Fieldmapper')) {
		my %hash = map { defined $fm->$_ ?
					($_ => $fm->$_) :
					()
				} grep { $_ ne $primary } $class->columns('All');

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
	my $orig = $self;

	my $class = ref($self) || $self;

	if (ref($arg) and UNIVERSAL::isa($arg => 'Fieldmapper')) {
		$self = $self->retrieve($arg);
		unless (defined $self) {
			$log->debug("ARG! Couldn't retrieve record ".$arg->id, DEBUG);
			throw OpenSRF::EX::WARN ("ARG! Couldn't retrieve record ");
		}
	}

	if ($class->find_column( 'last_xact_id' )) {
		my $xact_id = $self->current_xact_id;
		
		throw Error ("Deleting from $class requires a transaction be established")
			unless ($xact_id);
		
		throw Error ("The row you are attempting to delete has been changed since you read it")
			unless ( $orig->last_xact_id eq $self->last_xact_id);

		$self->last_xact_id( $class->current_xact_id );
		$self->SUPER::update;
	}

	$self->SUPER::delete;
	return 1;
}

sub update {
	my $self = shift;
	my $arg = shift;

	$log->debug("Attempting to update using $arg", DEBUG) if ($arg);

	if (ref($arg)) {
		$self = $self->modify_from_fieldmapper($arg);
		$log->debug("Modification of $self seems to have failed....", DEBUG);
		return undef unless (defined $self);
	}

	$log->debug("Calling Class::DBI->update on modified object $self", DEBUG);
	return $self->SUPER::update if ($self->is_changed);
	return 0;
}

sub modify_from_fieldmapper {
	my $obj = shift;
	my $fm = shift;
	my $orig = $obj;

	$log->debug("Modifying object using fieldmapper", DEBUG);

	my $class = ref($obj) || $obj;
	my ($primary) = $class->columns('Primary');

	if (!ref($obj)) {
		$obj = $class->retrieve($fm);
		unless ($obj) {
			$log->debug("Retrieve of $class using $fm (".$fm->id.") failed! -- ".shift(), ERROR);
			throw OpenSRF::EX::WARN ("No $class with id of ".$fm->id."!!");
		}
	}

	my %hash;
	
	if (ref($fm) and UNIVERSAL::isa($fm => 'Fieldmapper')) {
		%hash = map { defined $fm->$_ ?
				($_ => ''.$fm->$_) :
				()
			} grep { $_ ne $primary } $class->columns('All');
	} else {
		%hash = %{$fm};
	}

	my $au = $obj->autoupdate;
	$obj->autoupdate(0);
	
	for my $field ( keys %hash ) {
		$obj->$field( $hash{$field} ) if ($obj->$field ne $hash{$field});
		$log->debug("Setting field $field on $obj to $hash{$field}",INTERNAL);
	}

	if ($class->find_column( 'last_xact_id' ) and $obj->is_changed) {
		my $xact_id = $obj->current_xact_id;
		throw Error ("Updating $class requires a transaction be established")
			unless ($xact_id);
		throw Error ("The row you are attempting to delete has been changed since you read it")
			unless ( $orig->last_xact_id eq $self->last_xact_id);
		$obj->last_xact_id( $xact_id );
	} else {
		$obj->autoupdate($au)
	}

	return $obj;
}



	#-------------------------------------------------------------------------------
	actor::user->has_a( home_ou => 'actor::org_unit' );
	actor::user->has_a( card => 'actor::card' );
	actor::user->has_a( standing => 'config::standing' );
	actor::user->has_a( profile => 'actor::profile' );
	actor::user->has_a( mailing_address => 'actor::user_address' );
	actor::user->has_a( billing_address => 'actor::user_address' );
	actor::user->has_a( ident_type => 'config::identification_type' );
	actor::user->has_a( ident_type2 => 'config::identification_type' );
	actor::user->has_a( net_access_level => 'config::net_access_level' );

	actor::user_address->has_a( usr => 'actor::user' );
	
	actor::card->has_a( usr => 'actor::user' );
	
	actor::org_unit->has_a( parent_ou => 'actor::org_unit' );
	actor::org_unit->has_a( ou_type => 'actor::org_unit_type' );
	#actor::org_unit->has_a( address => 'actor::org_address' );

	actor::stat_cat_entry->has_a( stat_cat => 'actor::stat_cat' );
	actor::stat_cat->has_many( entries => 'actor::stat_cat_entry' );
	actor::stat_cat_entry_user_map->has_a( stat_cat => 'actor::stat_cat' );
	actor::stat_cat_entry_user_map->has_a( stat_cat_entry => 'actor::stat_cat_entry' );
	actor::stat_cat_entry_user_map->has_a( target_usr => 'actor::user' );

	asset::stat_cat_entry->has_a( stat_cat => 'asset::stat_cat' );
	asset::stat_cat->has_many( entries => 'asset::stat_cat_entry' );
	asset::stat_cat_entry_copy_map->has_a( stat_cat => 'asset::stat_cat' );
	asset::stat_cat_entry_copy_map->has_a( stat_cat_entry => 'asset::stat_cat_entry' );
	asset::stat_cat_entry_copy_map->has_a( owning_copy => 'asset::copy' );

	action::survey_response->has_a( usr => 'actor::user' );
	action::survey_response->has_a( survey => 'action::survey' );
	action::survey_response->has_a( question => 'action::survey_question' );
	action::survey_response->has_a( answer => 'action::survey_answer' );

	action::survey_question->has_a( survey => 'action::survey' );

	action::survey_answer->has_a( question => 'action::survey' );

	asset::copy_note->has_a( owning_copy => 'asset::copy' );

	actor::user->has_many( stat_cat_entries => [ 'actor::stat_cat_entry_user_map' => 'stat_cat_entry' ] );
	actor::user->has_many( stat_cat_entry_user_maps => 'actor::stat_cat_entry_user_map' );

	asset::copy->has_many( stat_cat_entries => [ 'asset::stat_cat_entry_copy_map' => 'stat_cat_entry' ] );
	asset::copy->has_many( stat_cat_entry_copy_maps => 'asset::stat_cat_entry_copy_map' );

	asset::copy->has_a( call_number => 'asset::call_number' );
	asset::copy->has_a( creator => 'actor::user' );
	asset::copy->has_a( editor => 'actor::user' );
	asset::copy->has_a( status => 'config::copy_status' );
	asset::copy->has_a( location => 'asset::copy_location' );
	asset::copy->has_a( circ_lib => 'actor::org_unit' );

	asset::call_number_note->has_a( call_number => 'asset::call_number' );

	asset::call_number->has_a( record => 'biblio::record_entry' );
	asset::call_number->has_a( creator => 'actor::user' );
	asset::call_number->has_a( editor => 'actor::user' );

	authority::record_note->has_a( record => 'authority::record_entry' );
	biblio::record_note->has_a( record => 'biblio::record_entry' );
	
	authority::record_entry->has_a( creator => 'actor::user' );
	authority::record_entry->has_a( editor => 'actor::user' );
	biblio::record_entry->has_a( creator => 'actor::user' );
	biblio::record_entry->has_a( editor => 'actor::user' );
	
	metabib::metarecord->has_a( master_record => 'biblio::record_entry' );
	
	authority::record_descriptor->has_a( record => 'authority::record_entry' );
	metabib::record_descriptor->has_a( record => 'biblio::record_entry' );
	
	authority::full_rec->has_a( record => 'authority::record_entry' );
	metabib::full_rec->has_a( record => 'biblio::record_entry' );
	
	metabib::title_field_entry->has_a( source => 'biblio::record_entry' );
	metabib::title_field_entry->has_a( field => 'config::metabib_field' );
	
	metabib::author_field_entry->has_a( source => 'biblio::record_entry' );
	metabib::author_field_entry->has_a( field => 'config::metabib_field' );
	
	metabib::subject_field_entry->has_a( source => 'biblio::record_entry' );
	metabib::subject_field_entry->has_a( field => 'config::metabib_field' );
	
	metabib::keyword_field_entry->has_a( source => 'biblio::record_entry' );
	metabib::keyword_field_entry->has_a( field => 'config::metabib_field' );
	
	metabib::series_field_entry->has_a( source => 'biblio::record_entry' );
	metabib::series_field_entry->has_a( field => 'config::metabib_field' );
	
	metabib::metarecord_source_map->has_a( metarecord => 'metabib::metarecord' );
	metabib::metarecord_source_map->has_a( source => 'biblio::record_entry' );

	action::circulation->has_a( usr => 'actor::user' );
	action::circulation->has_a( target_copy => 'asset::copy' );
	action::circulation->has_a( circ_lib => 'actor::org_unit' );

	money::billable_transaction->has_a( usr => 'actor::user' );
	
	
	#-------------------------------------------------------------------------------
	actor::user->has_many( survey_responses => 'action::survey_response' );
	actor::user->has_many( addresses => 'actor::user_address' );
	actor::user->has_many( cards => 'actor::card' );

	actor::org_unit->has_many( users => 'actor::user' );
	actor::profile->has_many( users => 'actor::user' );

	action::survey->has_many( questions => 'action::survey_question' );
	action::survey->has_many( responses => 'action::survey_response' );
	
	action::survey_question->has_many( answers => 'action::survey_answer' );
	action::survey_question->has_many( responses => 'action::survey_response' );

	action::survey_answer->has_many( responses => 'action::survey_response' );

	asset::copy->has_many( notes => 'asset::copy_note' );
	asset::call_number->has_many( copies => 'asset::copy' );
	asset::call_number->has_many( notes => 'asset::call_number_note' );

	authority::record_entry->has_many( record_descriptor => 'authority::record_descriptor' );
	authority::record_entry->has_many( notes => 'authority::record_note' );

	biblio::record_entry->has_many( record_descriptor => 'metabib::record_descriptor' );
	biblio::record_entry->has_many( notes => 'biblio::record_note' );
	biblio::record_entry->has_many( call_numbers => 'asset::call_number' );
	biblio::record_entry->has_many( full_record_entries => 'metabib::full_rec' );
	biblio::record_entry->has_many( title_field_entries => 'metabib::title_field_entry' );
	biblio::record_entry->has_many( author_field_entries => 'metabib::author_field_entry' );
	biblio::record_entry->has_many( subject_field_entries => 'metabib::subject_field_entry' );
	biblio::record_entry->has_many( keyword_field_entries => 'metabib::keyword_field_entry' );
	biblio::record_entry->has_many( series_field_entries => 'metabib::series_field_entry' );

	metabib::metarecord->has_many( source_records => [ 'metabib::metarecord_source_map' => 'source'] );

	money::billable_transaction->has_many( billings => 'money::billing' );
	money::billable_transaction->has_many( payments => 'money::payment' );

	money::billing->has_a( xact => 'money::billable_transaction' );
	money::payment->has_a( xact => 'money::billable_transaction' );

	money::cash_payment->has_a( xact => 'money::billable_transaction' );
	money::cash_payment->has_a( accepting_usr => 'actor::user' );

	money::check_payment->has_a( xact => 'money::billable_transaction' );
	money::check_payment->has_a( accepting_usr => 'actor::user' );

	money::credit_card_payment->has_a( xact => 'money::billable_transaction' );
	money::credit_card_payment->has_a( accepting_usr => 'actor::user' );

	money::forgive_payment->has_a( xact => 'money::billable_transaction' );
	money::forgive_payment->has_a( accepting_usr => 'actor::user' );

	money::work_payment->has_a( xact => 'money::billable_transaction' );
	money::work_payment->has_a( accepting_usr => 'actor::user' );

	money::credit_payment->has_a( xact => 'money::billable_transaction' );
	money::credit_payment->has_a( accepting_usr => 'actor::user' );

	permission::grp_tree->has_a( parent => 'permission::grp_tree' );

	permission::grp_perm_map->has_a( grp => 'permission::grp_tree' );
	permission::grp_perm_map->has_a(  perm => 'permission::perm_list' );
	permission::grp_perm_map->has_a(  depth => 'actor::org_unit_type' );
	
	permission::usr_perm_map->has_a( usr => 'actor::user' );
	permission::usr_perm_map->has_a(  perm => 'permission::perm_list' );
	permission::usr_perm_map->has_a(  depth => 'actor::org_unit_type' );
	
	permission::usr_grp_map->has_a(  usr => 'actor::user' );
	permission::usr_grp_map->has_a(  grp => 'permission::grp_tree' );

	action::hold_notification->has_a(  hold => 'action::hold_request' );
	
	action::hold_copy_map->has_a(  hold => 'action::hold_request' );
	action::hold_copy_map->has_a(  target_copy => 'asset::copy' );

	action::hold_request->has_a(  current_copy => 'asset::copy' );
	action::hold_request->has_a(  requestor => 'actor::user' );
	action::hold_request->has_a(  usr => 'actor::user' );
	action::hold_request->has_a(  pickup_lib => 'actor::org_unit' );

	action::hold_request->has_many(  notifications => 'action::hold_notification' );
	action::hold_request->has_many(  copy_maps => 'action::hold_copy_map' );

	asset::copy->has_many(  hold_maps => 'action::hold_copy_map' );

1;
