package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Application::Storage::CDBI::asset;
use OpenILS::Utils::Fieldmapper;

$VERSION = 1;

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
		SELECT	cn.record as record, count(cp.*) as copies
		  FROM	$cn_table cn
			JOIN $cp_table cp ON (cp.call_number = cn.id)
		  WHERE	cn.owning_lib LIKE ? AND
		  	cn.record IN ($rec_list)
		  GROUP BY cn.record
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

1;
