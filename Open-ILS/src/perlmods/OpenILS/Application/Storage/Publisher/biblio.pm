package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
#use OpenILS::Application::Storage::CDBI::biblio;
#use OpenILS::Application::Storage::CDBI::asset;
use OpenILS::Utils::Fieldmapper;

$VERSION = 1;

sub record_copy_count {
	my $self = shift;
	my $client = shift;

	my %args = @_;

	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;
	my $out_table = actor::org_unit_type->table;
	my $descendants = "actor.org_unit_descendants(u.id)";
	my $ancestors = "actor.org_unit_ancestors(?)";

	my $sql = <<"	SQL";
		SELECT	t.depth,
			u.id AS org_unit,
			sum(
				(SELECT count(cp.id)
				  FROM  $cn_table cn
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE cn.record = ?)
			) AS count,
			sum(
				(SELECT count(cp.id)
				  FROM  $cn_table cn
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $descendants a ON (cp.circ_lib = a.id)
				  WHERE cn.record = ?
				  	AND cp.status = 0)
			) AS available
		  FROM  $ancestors u
			JOIN $out_table t ON (u.ou_type = t.id)
		  GROUP BY 1,2
	SQL

	my $sth = biblio::record_entry->db_Main->prepare_cached($sql);
	$sth->execute(''.$args{record}, ''.$args{record}, ''.$args{org_unit});
	while ( my $row = $sth->fetchrow_hashref ) {
		$client->respond( $row );
	}
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.biblio.record_entry.copy_count',
	method		=> 'record_copy_count',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

sub record_by_barcode {
	my $self = shift;
	my $client = shift;

	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;

	my $id = ''.shift;
	my ($r) = biblio::record_entry->db_Main->selectrow_array( <<"	SQL", {}, $id );
		SELECT	cn.record
		  FROM	$cn_table cn
		  	JOIN $cp_table cp ON (cp.call_number = cn.id)
		  WHERE	cp.barcode = ?
	SQL

	my $rec = biblio::record_entry->retrieve( $r );

	return $rec->to_fieldmapper if ($rec);
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.biblio.record_entry.retrieve_by_barcode',
	method		=> 'record_by_barcode',
	api_level	=> 1,
	cachable	=> 1,
);

sub record_by_copy {
	my $self = shift;
	my $client = shift;

	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;

	my $id = ''.shift;
	my ($r) = biblio::record_entry->db_Main->selectrow_array( <<"	SQL", {}, $id );
		SELECT	cn.record
		  FROM	$cn_table cn
		  	JOIN $cp_table cp ON (cp.call_number = cn.id)
		  WHERE	cp.id = ?
	SQL

	my $rec = biblio::record_entry->retrieve( $r );
	my $r_fm = $rec->to_fieldmapper;
	$r_fm->fixed_fields( $rec->record_descriptor->next->to_fieldmapper );

	return $r_fm;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy',
	method		=> 'record_by_copy',
	api_level	=> 1,
	cachable	=> 1,
);


=comment Old version

my $org_unit_lookup;
sub record_copy_count {
	my $self = shift;
	my $client = shift;
	my $oid = shift;
	my @recs = @_;

	if ($self->api_name !~ /batch/o) {
		@recs = ($recs[0]);
	}

	throw OpenSRF::EX::InvalidArg ( "No org_unit id passed!" )
		unless ($oid);

	throw OpenSRF::EX::InvalidArg ( "No record id passed!" )
		unless (@recs);

	$org_unit_lookup ||= $self->method_lookup('open-ils.storage.direct.actor.org_unit.retrieve');
	my ($org_unit) = $org_unit_lookup->run($oid);

	# XXX Use descendancy tree here!!!
	my $short_name_hack = $org_unit->shortname;
	$short_name_hack = '' if (!$org_unit->parent_ou);
	$short_name_hack .= '%';
	# XXX Use descendancy tree here!!!

	my $rec_list = join(',',@recs);

	my $cp_table = asset::copy->table;
	my $cn_table = asset::call_number->table;

	my $select =<<"	SQL";
		SELECT	count(cp.*) as copies
		  FROM	$cn_table cn
			JOIN $cp_table cp ON (cp.call_number = cn.id)
		  WHERE	cn.owning_lib LIKE ? AND
		  	cn.record IN ($rec_list)
	SQL

	my $sth = asset::copy->db_Main->prepare_cached($select);
	$sth->execute($short_name_hack);

	my $results = $sth->fetchall_hashref('record');

	$client->respond($$results{$_}{copies} || 0) for (@recs);

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'record_copy_count',
	api_name	=> 'open-ils.storage.direct.biblio.record_copy_count',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'record_copy_count',
	api_name	=> 'open-ils.storage.direct.biblio.record_copy_count.batch',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);

=cut

sub global_record_copy_count {
	my $self = shift;
	my $client = shift;

	my $rec = shift;

	my $cn_table = asset::call_number->table;
	my $cp_table = asset::copy->table;
	my $cs_table = config::copy_status->table;

	my $copies_visible = 'AND cp.opac_visible IS TRUE AND cs.holdable IS TRUE';
	$copies_visible = '' if ($self->api_name =~ /staff/o);

	my $sql = <<"	SQL";

		SELECT	owning_lib, sum(avail), sum(tot)
 		  FROM	(
        			SELECT	owning_lib, count(cp.id) as avail, 0 as tot
				  FROM	$cn_table cn
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $cs_table cs ON (cs.id = cp.status)
				  WHERE	cn.record = ?
				  	AND cp.status = 0
				  	$copies_visible
				  GROUP BY 1
                        			UNION
        			SELECT	owning_lib, 0 as avail, count(cp.id) as tot
				  FROM	$cn_table cn
					JOIN $cp_table cp ON (cn.id = cp.call_number)
					JOIN $cs_table cs ON (cs.id = cp.status)
				  WHERE	cn.record = ?
				  	$copies_visible
				  GROUP BY 1
			) x
		  GROUP BY 1
	SQL

	my $sth = biblio::record_entry->db_Main->prepare_cached($sql);
	$sth->execute("$rec", "$rec");

	$client->respond( $_ ) for (@{$sth->fetchall_arrayref});
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.biblio.record_entry.global_copy_count',
	method		=> 'global_record_copy_count',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.biblio.record_entry.global_copy_count.staff',
	method		=> 'global_record_copy_count',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

1;
