package OpenILS::Application::Storage::Publisher::config;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::config;


sub metabib_field_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::metabib_field->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'metabib_field_all',
	api_name	=> 'open-ils.storage.direct.config.metabib_field.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub standing_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::standing->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'standing_all',
	api_name	=> 'open-ils.storage.direct.config.standing.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub ident_type_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::identification_type->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'ident_type_all',
	api_name	=> 'open-ils.storage.direct.config.identification_type.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub config_status_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::copy_status->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'config_status_all',
	api_name	=> 'open-ils.storage.direct.config.copy_status.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub config_non_cat {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::non_cataloged_type->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'config_non_cat',
	api_name	=> 'open-ils.storage.direct.config.non_cataloged_type.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);


# XXX arg, with the descendancy SPs...
sub ranged_config_non_cat {
	my $self = shift;
	my $client = shift;
	my @binds = @_;

	my $ctable = config::non_cataloged_type->table;

	my $descendants = defined($binds[1]) ?
		"actor.org_unit_full_path(?, ?)" :
		"actor.org_unit_full_path(?)" ;


	my $sql = <<"	SQL";
		SELECT	DISTINCT c.*
		  FROM	$ctable c
		  	JOIN $descendants d
				ON (d.id = c.owning_lib)
	SQL

	my $sth = config::non_cataloged_type->db_Main->prepare($sql);
	$sth->execute(@binds);

	while ( my $rec = $sth->fetchrow_hashref ) {

		my $cnct = new Fieldmapper::config::non_cataloged_type;
		$cnct->name($rec->{name});
		$cnct->owning_lib($rec->{owning_lib});
		$cnct->id($rec->{id});

		$client->respond( $cnct );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'ranged_config_non_cat',
	api_name	=> 'open-ils.storage.ranged.config.non_cataloged_type.retrieve',
	argc		=> 1,
	stream		=> 1,
	notes		=> <<"	NOTES",
		Returns 
	NOTES
);

1;
