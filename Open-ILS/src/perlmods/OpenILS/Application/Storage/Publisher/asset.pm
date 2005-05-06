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
	my @ids = @_;

	return undef unless (@ids);

	@ids = ($ids[0]) unless ($self->api_name =~ /batch/o);

	for my $id ( @ids ) {
		next unless $id;
		my $cp = asset::copy->retrieve($id);

		my $cp_fm = $cp->to_fieldmapper;
		$cp_fm->circ_lib( $cp->circ_lib->to_fieldmapper );
		$cp_fm->location( $cp->location->to_fieldmapper );
		$cp_fm->status( $cp->status->to_fieldmapper );
		my @scs;
		for my $map ( $cp->stat_cat_entry_copy_maps ) {
			push @scs, $map->to_fieldmapper;
		}
		$cp_fm->stat_cat_entries( \@scs );

		$client->respond( $cp_fm );
	}

	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.asset.copy.batch.retrieve',
	method		=> 'fleshed_copy',
	argc		=> 1,
	stream		=> 1,
);
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

#XXX Fix stored proc calls
sub ranged_asset_stat_cat {
        my $self = shift;
        my $client = shift;
        my $ou = ''.shift();

        return undef unless ($ou);
        my $s_table = asset::stat_cat->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
                        JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
                  ORDER BY name
        SQL

        $fleshed = 0;
        $fleshed = 1 if ($self->api_name =~ /fleshed/o);

        my $sth = asset::stat_cat->db_Main->prepare_cached($select);
        $sth->execute($ou);

        for my $sc ( map { asset::stat_cat->construct($_) } $sth->fetchall_hash ) {
                my $sc_fm = $sc->to_fieldmapper;
                $sc_fm->entries(
                        [ $self->method_lookup( 'open-ils.storage.ranged.asset.stat_cat_entry.search.stat_cat' )->run($ou,$sc->id) ]
                ) if ($fleshed);
                $client->respond( $sc_fm );
        }

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.fleshed.asset.stat_cat.all',
        api_level       => 1,
        stream          => 1,
        method          => 'ranged_asset_stat_cat',
);

__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.asset.stat_cat.all',
        api_level       => 1,
        stream          => 1,
        method          => 'ranged_asset_stat_cat',
);


#XXX Fix stored proc calls
sub multiranged_asset_stat_cat {
        my $self = shift;
        my $client = shift;
        my $ous = shift;

        return undef unless (defined($ous) and @$ous);
        my $s_table = asset::stat_cat->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
		  WHERE s.owner IN ( XXX )
                  ORDER BY name
        SQL

	my $binds = join(' INTERSECT ', map { 'SELECT id FROM actor.org_unit_full_path(?)' } grep {defined} @$ous);
	$select =~ s/XXX/$binds/so;
	
        $fleshed = 0;
        $fleshed = 1 if ($self->api_name =~ /fleshed/o);

        my $sth = asset::stat_cat->db_Main->prepare_cached($select);
        $sth->execute(map { "$_" } grep {defined} @$ous);

        for my $sc ( map { asset::stat_cat->construct($_) } $sth->fetchall_hash ) {
                my $sc_fm = $sc->to_fieldmapper;
                $sc_fm->entries(
                        [ $self->method_lookup( 'open-ils.storage.multiranged.asset.stat_cat_entry.search.stat_cat' )->run($ous, $sc->id) ]
                ) if ($fleshed);
                $client->respond( $sc_fm );
        }

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.multiranged.fleshed.asset.stat_cat.all',
        api_level       => 1,
        stream          => 1,
        method          => 'multiranged_asset_stat_cat',
);

#XXX Fix stored proc calls
sub ranged_asset_stat_cat_entry {
        my $self = shift;
        my $client = shift;
        my $ou = ''.shift();
        my $sc = ''.shift();

        return undef unless ($ou);
        my $s_table = asset::stat_cat_entry->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
                        JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
                  WHERE stat_cat = ?
                  ORDER BY name
        SQL

        my $sth = asset::stat_cat->db_Main->prepare_cached($select);
        $sth->execute($ou,$sc);

        for my $sce ( map { asset::stat_cat_entry->construct($_) } $sth->fetchall_hash ) {
                $client->respond( $sce->to_fieldmapper );
        }

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.ranged.asset.stat_cat_entry.search.stat_cat',
        api_level       => 1,
        stream          => 1,
        method          => 'ranged_asset_stat_cat_entry',
);

#XXX Fix stored proc calls
sub multiranged_asset_stat_cat_entry {
        my $self = shift;
        my $client = shift;
        my $ous = shift;
        my $sc = ''.shift();

        return undef unless (defined($ous) and @$ous);
        my $s_table = asset::stat_cat_entry->table;

        my $select = <<"        SQL";
                SELECT  s.*
                  FROM  $s_table s
		  WHERE s.owner IN ( XXX ) and s.stat_cat = ?
                  ORDER BY value
        SQL

	my $binds = join(' INTERSECT ', map { 'SELECT id FROM actor.org_unit_full_path(?)' } grep {defined} @$ous);
	$select =~ s/XXX/$binds/so;
	
        my $sth = asset::stat_cat->db_Main->prepare_cached($select);
        $sth->execute(map {"$_"} @$ous,$sc);

        for my $sce ( map { asset::stat_cat_entry->construct($_) } $sth->fetchall_hash ) {
                $client->respond( $sce->to_fieldmapper );
        }

        return undef;
}
__PACKAGE__->register_method(
        api_name        => 'open-ils.storage.multiranged.asset.stat_cat_entry.search.stat_cat',
        api_level       => 1,
        stream          => 1,
        method          => 'multiranged_asset_stat_cat_entry',
);



1;
