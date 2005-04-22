package OpenILS::Application::Storage::Publisher::action;
use base qw/OpenILS::Application::Storage/;
#use OpenILS::Application::Storage::CDBI::action;
#use OpenSRF::Utils::Logger qw/:level/;
#use OpenILS::Utils::Fieldmapper;
#
#my $log = 'OpenSRF::Utils::Logger';

sub find_opac_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	action.survey s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.opac IS TRUE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.opac',
	api_level       => 1,
	stream          => 1,
	method          => 'find_opac_surveys',
);

sub find_optional_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	action.survey s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.required IS FALSE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.optional',
	api_level       => 1,
	stream          => 1,
	method          => 'find_optional_surveys',
);

sub find_required_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	action.survey s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.required IS TRUE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.required',
	api_level       => 1,
	stream          => 1,
	method          => 'find_required_surveys',
);




1;
