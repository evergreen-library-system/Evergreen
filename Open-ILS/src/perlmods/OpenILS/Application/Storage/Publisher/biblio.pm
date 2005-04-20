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

1;
