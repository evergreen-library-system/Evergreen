package OpenILS::Application::Storage::Publisher::config;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::config;


sub retrieve_all {
	my $self = shift;
	my $client = shift;

	$self->api_name =~ /direct\.config\.(.+)\.retrieve/o;
	
	my $class = 'config::'.$1;
	for my $rec ( $class->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}

for my $class (
		qw/metabib_field standing identification_type copy_status
		   non_cataloged_type audience_map item_form_map item_type_map
		   language_map lit_form_map bib_source net_access_level/ ) {

	__PACKAGE__->register_method(
		method		=> 'retrieve_all',
		api_name	=> "open-ils.storage.direct.config.$class.retrieve.all",
		argc		=> 0,
		stream		=> 1,
	);
}


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
		$cnct->circ_duration($rec->{circ_duration});

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
