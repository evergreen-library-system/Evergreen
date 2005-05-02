package OpenILS::Application::Storage::Publisher::asset;
use base qw/OpenILS::Application::Storage/;
#use OpenILS::Application::Storage::CDBI::asset;
#use OpenSRF::Utils::Logger qw/:level/;
#use OpenILS::Utils::Fieldmapper;
#
#my $log = 'OpenSRF::Utils::Logger';

sub asset_copy_location_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( asset::copy_location->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'asset_copy_location_all',
	api_name	=> 'open-ils.storage.direct.asset.copy_location.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub fleshed_copy {
	my $self = shift;
	my $client = shift;
	my $id = ''.shift;

	my $cp = asset::copy->retrieve($id);

	my $cp_fm = $cp->to_fieldmapper;
	$cp_fm->circ_lib( $cp->circ_lib->to_fieldmapper );
	$cp_fm->location( $cp->location->to_fieldmapper );
	$cp_fm->status( $cp->status->to_fieldmapper );
	return $cp_fm;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.asset.copy.retrieve',
	method		=> 'fleshed_copy',
	argc		=> 1,
);

sub fleshed_copy_by_barcode {
	my $self = shift;
	my $client = shift;
	my $bc = ''.shift;

	my ($cp) = asset::copy->search( { barcode => $bc } );

	my $cp_fm = $cp->to_fieldmapper;
	$cp_fm->circ_lib( $cp->circ_lib->to_fieldmapper );
	$cp_fm->location( $cp->location->to_fieldmapper );
	$cp_fm->status( $cp->status->to_fieldmapper );

	return [ $cp_fm ];
}	
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.asset.copy.search.barcode',
	method		=> 'fleshed_copy_by_barcode',
	argc		=> 1,
	stream		=> 1,
);


1;
