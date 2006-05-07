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
use OpenILS::Application::Storage::CDBI::container;

use JSON;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::EX qw/:try/;

our $VERSION = 1;
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
	my $field_list = join ',', $class->columns('Essential');
	
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
	if (ref($arg) &&
		(UNIVERSAL::isa($arg => 'Fieldmapper') ||
		 UNIVERSAL::isa($arg => 'Class::DBI')) ) {
		my ($col) = $self->primary_column;
		$log->debug("Using field $col as the primary key", INTERNAL);
		$arg = $arg->$col;
	} elsif (ref $arg) {
		my ($col) = $self->primary_column;
		$log->debug("Using field $col as the primary key", INTERNAL);
		$arg = $arg->{$col};
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

	$log->debug("CDBI->merge: \$search is $search (".ref($search)." : ".join(',',map{"$_ => $$search{$_}"}keys(%$search)).")",DEBUG);
	$log->debug("CDBI->merge: \$arg is $arg (".ref($arg)." : ".join(',',map{"$_ => $$arg{$_}"}keys(%$arg)).")",DEBUG);

	my @objs = ($self);
	@objs = $self->search_where($search) unless (ref $self);

	if (@objs == 1) {
		$objs[0]->update($arg);
		return $objs[0];
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

	$log->debug("CDBI->remote_update: \$search is $search (".ref($search)." : ".join(',',map{"$_ => $$search{$_}"}keys(%$search)).")",DEBUG);
	$log->debug("CDBI->remote_update: \$arg is $arg (".ref($arg)." : ".join(',',map{"$_ => $$arg{$_}"}keys(%$arg)).")",DEBUG);

#	my @objs = $self->search_where($search);
#	throw OpenSRF::EX::WARN ("No objects found for remote_update.  Perhaps you meant to use merge?")
#		if (@objs == 0);

#	$_->update($arg) for (@objs);
#	return scalar(@objs);

	my @finds = sort keys %$search;
	my @sets = sort keys %$arg;

	my @find_vals = @$search{@finds};
	my @set_vals = @$arg{@sets};

	my $sql = 'UPDATE %s SET %s WHERE %s';

	my $table = $self->table;
	my $set = join(', ', map { "$_=?" } @sets);
	my $where = join(', ', map { "$_=?" } @finds);

	my $sth = $self->db_Main->prepare(sprintf($sql, $table, $set, $where));
	$sth->execute(@set_vals,@find_vals);
	return $sth->rows;

}

sub create {
	my $self = shift;
	my $arg = shift;

	$log->debug("CDBI->create: \$arg is $arg (".ref($arg)." : ".JSON->perl2JSON($arg).")",DEBUG);

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
				} grep { $_ ne $primary } $class->columns('Essential');

		if ($class->find_column( 'last_xact_id' )) {
			if ($OpenILS::Application::Storage::IGNORE_XACT_ID_FAILURE) {
				$hash{last_xact_id} = 'unknown.'.time.'.'.$$.'.'.rand($$);
			} else {
				my $xact_id = $class->current_xact_id;
				throw Error unless ($xact_id);
				$hash{last_xact_id} = $xact_id;
			}
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

	$self = $self->retrieve($arg) if (!ref($self));
	unless (defined $self) {
		$log->debug("ARG! Couldn't retrieve record ".$arg->id, DEBUG);
		throw OpenSRF::EX::WARN ("ARG! Couldn't retrieve record ");
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

sub debug_object {
	my $obj = shift;
	my $string = '';

	$string .= "Object type:\t".ref($obj)."\n";
	$string .= "Object string:\t$obj\n";

	if (ref($obj) && UNIVERSAL::isa($obj => 'Fieldmapper')) {
		$string .= "Object fields:\n";
		for my $col ($obj->real_fields()) {
			$string .= "\t$col\t=> ".$obj->$col."\n";
		}
	} elsif (ref($obj) && UNIVERSAL::isa($obj => 'Class::DBI')) {
		$string .= "Object cols:\n";
		for my $col ($obj->columns('All')) {
			$string .= "\t$col\t=> ".$obj->$col."\n";
		}
	} elsif (ref($obj) && UNIVERSAL::isa($obj => 'HASH')) {
		$string .= "Object keys and vals:\n";
		for my $col (keys %$obj) {
			$string .= "\t$col\t=> $$obj{$col}\n";
		}
	}

	$string .= "\n";
	
	$log->debug($string,DEBUG);
}


sub update {
	my $self = shift;
	my $arg = shift;

	$log->debug("Attempting to update using $arg", DEBUG) if ($arg);

	if (ref($arg)) {
		$self = $self->modify_from_fieldmapper($arg);
		unless (defined $self) {
			$log->debug("Modification of $arg seems to have failed....", DEBUG);
			return undef;
		}
	}

	$log->debug("Calling Class::DBI->update on modified object $self", DEBUG);

	#debug_object($self);

	return $self->SUPER::update if ($self->is_changed);
	return 0;
}

sub modify_from_fieldmapper {
	my $obj = shift;
	my $fm = shift;
	my $orig = $obj;

	#debug_object($obj);
	#debug_object($fm);

	$log->debug("Modifying object using fieldmapper", DEBUG);

	my $class = ref($obj) || $obj;
	my ($primary) = $class->columns('Primary');


	if (!ref($obj)) {
		$obj = $class->retrieve($fm);
		#debug_object($obj);
		unless ($obj) {
			$log->debug("Retrieve of $class using $fm (".$fm->id.") failed! -- ".shift(), ERROR);
			throw OpenSRF::EX::WARN ("No $class with id of ".$fm->id."!!");
		}
	}

	my %hash;
	
	if (ref($fm) and UNIVERSAL::isa($fm => 'Fieldmapper')) {
		%hash = map { ($_ => $fm->$_) } grep { $_ ne $primary } $class->columns('Essential');
		delete $hash{passwd} if ($fm->isa('Fieldmapper::actor::user'));
	} else {
		%hash = %{$fm};
	}

	my $au = $obj->autoupdate;
	$obj->autoupdate(0);
	
	#debug_object($obj);

	for my $field ( keys %hash ) {
		$obj->$field( $hash{$field} ) if ($obj->$field ne $hash{$field});
		$log->debug("Setting field $field on $obj to $hash{$field}",INTERNAL);
	}

	if ($class->find_column( 'last_xact_id' ) and $obj->is_changed) {
		my ($xact_id) = OpenILS::Application::Storage->method_lookup('open-ils.storage.transaction.current')->run();
		throw Error ("Updating $class requires a transaction be established")
			unless ($xact_id);
		throw Error ("The row you are attempting to delete has been changed since you read it")
			unless ( $fm->last_xact_id eq $obj->last_xact_id);
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
	
	actor::workstation->has_a( owning_lib => 'actor::org_unit' );
	actor::org_unit::closed_date->has_a( org_unit => 'actor::org_unit' );
	actor::org_unit_setting->has_a( org_unit => 'actor::org_unit' );

	actor::usr_note->has_a( usr => 'actor::user' );
	actor::user->has_many( notes => 'actor::usr_note' );

	actor::user_standing_penalty->has_a( usr => 'actor::user' );
	actor::user->has_many( standing_penalties => 'actor::user_standing_penalty' );

	actor::org_unit->has_a( parent_ou => 'actor::org_unit' );
	actor::org_unit->has_a( ou_type => 'actor::org_unit_type' );
	actor::org_unit->has_a( ill_address => 'actor::org_address' );
	actor::org_unit->has_a( holds_address => 'actor::org_address' );
	actor::org_unit->has_a( mailing_address => 'actor::org_address' );
	actor::org_unit->has_a( billing_address => 'actor::org_address' );
	actor::org_unit->has_many( children => 'actor::org_unit' => 'parent_ou' );
	actor::org_unit->has_many( workstations => 'actor::workstation' );
	actor::org_unit->has_many( closed_dates => 'actor::org_unit::closed_date' );
	actor::org_unit->has_many( settings => 'actor::org_unit_setting' );
	#actor::org_unit->might_have( hours_of_operation => 'actor::org_unit::hours_of_operation' );

	actor::org_unit_type->has_a( parent => 'actor::org_unit_type' );
	actor::org_unit_type->has_many( children => 'actor::org_unit_type' => 'parent' );

	actor::org_address->has_a( org_unit => 'actor::org_unit' );
	actor::org_unit->has_many( addresses => 'actor::org_address' );

	action::transit_copy->has_a( source => 'actor::org_unit' );
	action::transit_copy->has_a( dest => 'actor::org_unit' );
	action::transit_copy->has_a( copy_status => 'config::copy_status' );

	action::hold_transit_copy->has_a( source => 'actor::org_unit' );
	action::hold_transit_copy->has_a( dest => 'actor::org_unit' );
	action::hold_transit_copy->has_a( copy_status => 'config::copy_status' );
	action::hold_transit_copy->has_a( hold => 'action::hold_request' );

	action::hold_request->has_many( transits => 'action::hold_transit_copy' );

	actor::stat_cat_entry->has_a( stat_cat => 'actor::stat_cat' );
	actor::stat_cat->has_a( owner => 'actor::org_unit' );
	actor::stat_cat->has_many( entries => 'actor::stat_cat_entry' );
	actor::stat_cat_entry_user_map->has_a( stat_cat => 'actor::stat_cat' );
	actor::stat_cat_entry_user_map->has_a( stat_cat_entry => 'actor::stat_cat_entry' );
	actor::stat_cat_entry_user_map->has_a( target_usr => 'actor::user' );

	asset::stat_cat_entry->has_a( stat_cat => 'asset::stat_cat' );
	asset::stat_cat->has_a( owner => 'actor::org_unit' );
	asset::stat_cat->has_many( entries => 'asset::stat_cat_entry' );
	asset::stat_cat_entry_copy_map->has_a( stat_cat => 'asset::stat_cat' );
	asset::stat_cat_entry_copy_map->has_a( stat_cat_entry => 'asset::stat_cat_entry' );
	asset::stat_cat_entry_copy_map->has_a( owning_copy => 'asset::copy' );

	action::survey_response->has_a( usr => 'actor::user' );
	action::survey_response->has_a( survey => 'action::survey' );
	action::survey_response->has_a( question => 'action::survey_question' );
	action::survey_response->has_a( answer => 'action::survey_answer' );

	action::survey_question->has_a( survey => 'action::survey' );

	action::survey_answer->has_a( question => 'action::survey_question' );

	asset::copy_note->has_a( owning_copy => 'asset::copy' );
	asset::copy_note->has_a( creator => 'actor::user' );

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
	actor::user->has_many( circulations => 'action::circulation' => 'usr' );
	
	action::circulation->has_a( circ_staff => 'actor::user' );
	actor::user->has_many( performed_circulations => 'action::circulation' => 'circ_staff' );

	action::circulation->has_a( checkin_staff => 'actor::user' );
	actor::user->has_many( checkins => 'action::circulation' => 'checkin_staff' );

	action::circulation->has_a( target_copy => 'asset::copy' );
	asset::copy->has_many( circulations => 'action::circulation' => 'target_copy' );

	action::circulation->has_a( circ_lib => 'actor::org_unit' );
	actor::org_unit->has_many( circulations => 'action::circulation' => 'circ_lib' );
	
	action::circulation->has_a( checkin_lib => 'actor::org_unit' );
	actor::org_unit->has_many( checkins => 'action::circulation' => 'checkin_lib' );

	money::billable_transaction->has_a( usr => 'actor::user' );
	money::billable_transaction->might_have( circulation => 'action::circulation' );
	money::billable_transaction->might_have( grocery => 'money::grocery' );
	actor::user->has_many( billable_transactions => 'action::circulation' => 'usr' );
	
	
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
	biblio::record_entry->has_many( metarecords => [ 'metabib::metarecord_source_map' => 'metarecord'] );

	money::billable_transaction->has_many( billings => 'money::billing' );
	money::billable_transaction->has_many( payments => 'money::payment' );

	action::circulation->has_many( billings => 'money::billing' => 'xact' );
	action::circulation->has_many( payments => 'money::payment' => 'xact' );
	action::circulation->might_have( billable_transaction => 'money::billable_transaction' );

	action::open_circulation->might_have( circulation => 'action::circulation' );

	action::in_house_use->has_a( org_unit => 'actor::org_unit' );
	action::in_house_use->has_a( staff => 'actor::user' );
	action::in_house_use->has_a( item => 'asset::copy' );

	action::non_cataloged_circulation->has_a( circ_lib => 'actor::org_unit' );
	action::non_cataloged_circulation->has_a( item_type => 'config::non_cataloged_type' );
	action::non_cataloged_circulation->has_a( patron => 'actor::user' );
	action::non_cataloged_circulation->has_a( staff => 'actor::user' );

	money::grocery->has_many( billings => 'money::billing' => 'xact' );
	money::grocery->has_many( payments => 'money::payment' => 'xact' );
	money::grocery->might_have( billable_transaction => 'money::billable_transaction' );

	money::billing->has_a( xact => 'money::billable_transaction' );
	money::payment->has_a( xact => 'money::billable_transaction' );
	money::payment->might_have( cash_payment => 'money::cash_payment' );
	money::payment->might_have( check_payment => 'money::check_payment' );
	money::payment->might_have( credit_card_payment => 'money::credit_card_payment' );
	money::payment->might_have( forgive_payment => 'money::forgive_payment' );
	money::payment->might_have( work_payment => 'money::work_payment' );
	money::payment->might_have( credit_payment => 'money::credit_payment' );

	money::cash_payment->has_a( xact => 'money::billable_transaction' );
	money::cash_payment->has_a( accepting_usr => 'actor::user' );
	money::cash_payment->might_have( payment => 'money::payment' );

	money::check_payment->has_a( xact => 'money::billable_transaction' );
	money::check_payment->has_a( accepting_usr => 'actor::user' );
	money::check_payment->might_have( payment => 'money::payment' );

	money::credit_card_payment->has_a( xact => 'money::billable_transaction' );
	money::credit_card_payment->has_a( accepting_usr => 'actor::user' );
	money::credit_card_payment->might_have( payment => 'money::payment' );

	money::forgive_payment->has_a( xact => 'money::billable_transaction' );
	money::forgive_payment->has_a( accepting_usr => 'actor::user' );
	money::forgive_payment->might_have( payment => 'money::payment' );

	money::work_payment->has_a( xact => 'money::billable_transaction' );
	money::work_payment->has_a( accepting_usr => 'actor::user' );
	money::work_payment->might_have( payment => 'money::payment' );

	money::credit_payment->has_a( xact => 'money::billable_transaction' );
	money::credit_payment->has_a( accepting_usr => 'actor::user' );
	money::credit_payment->might_have( payment => 'money::payment' );

	permission::grp_tree->has_a( parent => 'permission::grp_tree' );
	permission::grp_tree->has_many( children => 'permission::grp_tree' => 'parent' );

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

	action::unfulfilled_hold_list->has_a(  current_copy => 'asset::copy' );
	action::unfulfilled_hold_list->has_a(  hold => 'action::hold_request' );
	action::unfulfilled_hold_list->has_a(  circ_lib => 'actor::org_unit' );

	action::hold_request->has_a(  current_copy => 'asset::copy' );
	action::hold_request->has_a(  requestor => 'actor::user' );
	action::hold_request->has_a(  usr => 'actor::user' );
	action::hold_request->has_a(  fulfillment_staff => 'actor::user' );
	action::hold_request->has_a(  pickup_lib => 'actor::org_unit' );
	action::hold_request->has_a(  request_lib => 'actor::org_unit' );
	action::hold_request->has_a(  fulfillment_lib => 'actor::org_unit' );
	action::hold_request->has_a(  selection_ou => 'actor::org_unit' );

	action::hold_request->has_many(  notifications => 'action::hold_notification' );
	action::hold_request->has_many(  eligible_copies => [ 'action::hold_copy_map' => 'target_copy' ] );

	asset::copy->has_many(  holds => [ 'action::hold_copy_map' => 'hold' ] );

	container::biblio_record_entry_bucket->has_a( owner => 'actor::user' );
	container::biblio_record_entry_bucket_item->has_a( bucket => 'container::biblio_record_entry_bucket' );
	container::biblio_record_entry_bucket_item->has_a( target_biblio_record_entry => 'biblio::record_entry' );
	container::biblio_record_entry_bucket->has_many( items => 'container::biblio_record_entry_bucket_item' );

	container::user_bucket->has_a( owner => 'actor::user' );
	container::user_bucket_item->has_a( bucket => 'container::user_bucket' );
	container::user_bucket_item->has_a( target_user => 'actor::user' );
	container::user_bucket->has_many( items => 'container::user_bucket_item' );

	container::call_number_bucket->has_a( owner => 'actor::user' );
	container::call_number_bucket_item->has_a( bucket => 'container::call_number_bucket' );
	container::call_number_bucket_item->has_a( target_call_number => 'asset::call_number' );
	container::call_number_bucket->has_many( items => 'container::call_number_bucket_item' );

	container::copy_bucket->has_a( owner => 'actor::user' );
	container::copy_bucket_item->has_a( bucket => 'container::copy_bucket' );
	container::copy_bucket_item->has_a( target_copy => 'asset::copy' );
	container::copy_bucket->has_many( items => 'container::copy_bucket_item' );


1;
