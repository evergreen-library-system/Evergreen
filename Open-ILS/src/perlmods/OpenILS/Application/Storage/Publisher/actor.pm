package OpenILS::Application::Storage::Publisher::actor;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::actor;
use OpenSRF::Utils::Logger qw/:level/;
use OpenILS::Utils::Fieldmapper;

my $log = 'OpenSRF::Utils::Logger';

sub org_unit_list {
	my $self = shift;
	my $client = shift;

	my $select =<<"	SQL";
	SELECT	*
	  FROM	actor.org_unit
	  ORDER BY CASE WHEN parent_ou IS NULL THEN 0 ELSE 1 END, name;
	SQL

	my $sth = actor::org_unit->db_Main->prepare_cached($select);
	$sth->execute;

	my @fms;
	push @fms, $_->to_fieldmapper for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return \@fms;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.org_unit.retrieve.all',
	api_level	=> 1,
	method		=> 'org_unit_list',
);

sub org_unit_type_list {
	my $self = shift;
	my $client = shift;

	my $select =<<"	SQL";
	SELECT	*
	  FROM	actor.org_unit_type
	  ORDER BY depth, name;
	SQL

	my $sth = actor::org_unit_type->db_Main->prepare_cached($select);
	$sth->execute;

	my @fms;
	push @fms, $_->to_fieldmapper for ( map { actor::org_unit_type->construct($_) } $sth->fetchall_hash );

	return \@fms;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.direct.actor.org_unit_type.retrieve.all',
	api_level	=> 1,
	method		=> 'org_unit_type_list',
);

sub org_unit_descendants {
	my $self = shift;
	my $client = shift;
	my $id = shift;

	return undef unless ($id);

	my $select =<<"	SQL";
	SELECT	a.*
	  FROM	connectby('actor.org_unit','id','parent_ou','name',?,'100','.')
	  		as t(keyid text, parent_keyid text, level int, branch text,pos int),
		actor.org_unit a
	  WHERE	t.keyid = a.id
	  ORDER BY t.pos;
	SQL

	my $sth = actor::org_unit->db_Main->prepare_cached($select);
	$sth->execute($id);

	my @fms;
	push @fms, $_->to_fieldmapper for ( map { actor::org_unit->construct($_) } $sth->fetchall_hash );

	return \@fms;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.actor.org_unit.descendants',
	api_level	=> 1,
	method		=> 'org_unit_descendants',
);


1;
