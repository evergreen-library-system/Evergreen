package OpenILS::Application::Storage;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;

use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/:level/;

my $log = "OpenSRF::Utils::Logger";

sub DESTROY {};

our $_db_driver;
our $_db_params;

sub driver {
	return $_db_driver;
}

sub initialize {
	return $_db_driver if (defined $_db_driver);
	my $conf = OpenSRF::Utils::SettingsClient->new;

	$log->debug('Initializing ' . __PACKAGE__ . '...', DEBUG);

	my $driver = $conf->get_value( apps => storage => app_settings => databases => 'driver');
	my $_db_params = $conf->get_value( apps => storage => app_settings => databases => 'database');

	$_db_driver = "OpenILS::App::Storage::Driver::$driver";


	eval "use $_db_driver;";
	throw OpenILS::EX::Config ( "Can't load $_db_driver!  :  $@" ) if ($@);

	$_db_driver->initialize if ($_db_driver->can('initialize'));

	push @OpenILS::Application::Storage::CDBI::ISA, $_db_driver;

}

sub child_init {

	$log->debug('Running child_init for ' . __PACKAGE__ . '...', DEBUG);
	$_db_driver->child_init if ($_db_driver->can('child_init'));
	
	return 1 if ($_db_driver->db_Main($_db_params));
	return 0;
}

sub getBiblioFieldMaps {
	my $self = shift;
	my $client = shift;
	my $id = shift;
	$log->debug(" Executing [".$self->method."] as [".$self->api_name."]",INTERNAL);
	
	if ($self->api_name =~ /by_class$/) {
		if ($id) {
			return _cdbi2Hash( config::metarecord_field_map->search( fieldclass => $id ) );
		} else {
			throw OpenSRF::EX::InvalidArg ('Please give me a Class to look up!');
		}
	} else {
		if ($id) {
			return _cdbi2Hash( config::metarecord_field_map->retrieve( $id ) );
		} else {
			return _cdbi_list2AoH( config::metarecord_field_map->retrieve_all );
		}
	}
}	
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMaps',
	api_name	=> 'open-ils.storage.config.metarecord_field',
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMaps',
	api_name	=> 'open-ils.storage.config.metarecord_field.list',
	argc		=> 0,
);
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMaps',
	api_name	=> 'open-ils.storage.config.metarecord_field.list.by_class',
	argc		=> 1,
);


sub getBiblioFieldMapClasses {
	my $self = shift;
	my $client = shift;
	my $id = shift;

	$log->debug(" Executing [".$self->method."] as [".$self->api_name."]",INTERNAL);

	if ($id) {
		return _cdbi2Hash( config::metarecord_field_class_map->retrieve( $id ) );
	} else {
		return _cdbi_list2AoH( config::metarecord_field_class_map->retrieve_all );
	}
}	
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMapClasses',
	api_name	=> 'open-ils.storage.config.metarecord_field_class',
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMapClasses',
	api_name	=> 'open-ils.storage.config.metarecord_field_class.list',
	argc		=> 0,
);

sub _cdbi2Hash {
	my $obj = shift;
	return { map { ( $_ => $obj->$_ ) } $obj->columns };
}

sub _cdbi_list2AoH {
	my @objs = @_;
	return [ map { _cdbi2oilsHash($_) } @objs ];
}

#-------------------------------------------------------------------------------
package OpenILS::App::Storage::CDBI;
use vars qw/@ISA/;

1;
