package OpenILS::Application::Storage::Publisher::permission;
use base qw/OpenILS::Application::Storage/;
#use OpenILS::Application::Storage::CDBI::config;


sub usr_has_perm {
	my $self = shift;
	my $client = shift;
	my $usr = shift;
	my $perm = shift;
	my $target = shift;

	return permission::usr_grp_map->db_Main->selectrow_arrayref(<<"	SQL",{}, "$usr", "$perm", "$target")->[0];
		SELECT permission.usr_has_perm(?,?,?)
	SQL
}
__PACKAGE__->register_method(
	method		=> 'usr_has_perm',
	api_name	=> 'open-ils.storage.permission.user_has_perm',
	argc		=> 3,
);

sub usr_perms {
	my $self = shift;
	my $client = shift;
	my $usr = shift;

	my $sth = permission::usr_perm_map->db_Main->prepare('SELECT DISTINCT * FROM permission.usr_perms(?)');
	$sth->execute("$usr");

	$client->respond( $_->to_fieldmapper ) for ( map { permission::usr_perm_map->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'usr_perms',
	api_name	=> 'open-ils.storage.permission.user_perms',
	argc		=> 2,
	stream		=> 1,
);

1;
