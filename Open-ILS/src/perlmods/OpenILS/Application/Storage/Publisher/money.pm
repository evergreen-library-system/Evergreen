package OpenILS::Application::Storage::Publisher::money;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::Utils::Logger qw/:level/;

my $log = 'OpenSRF::Utils::Logger';

sub new_collections {
	my $self = shift;
	my $client = shift;
	my $age = shift;
	my $amount = shift;
	my @loc = @_;

	my $mct = money::collections_tracker->table;
	my $mb = money::billing->table;
	my $circ = action::circulation->table;
	my $mg = money::grocery->table;
	my $descendants = "actor.org_unit_descendants((select id from actor.org_unit where shortname = ?))";

	my $SQL = <<"	SQL";
		SELECT	lt.usr,
			MAX(bl.billing_ts) AS last_pertinent_billing,
			SUM(bl.amount) - COALESCE(SUM((SELECT SUM(amount) FROM money.payment WHERE xact = lt.id)),0) AS threshold_amount
		  FROM	( SELECT id,usr,billing_location AS location FROM money.grocery
		  		UNION ALL
			  SELECT id,usr,circ_lib AS location FROM action.circulation ) AS lt
			JOIN $descendants d ON (lt.location = d.id)
			JOIN money.billing bl ON (lt.id = bl.xact AND bl.voided IS FALSE)
		  WHERE	AGE(bl.billing_ts) > ?
		  GROUP BY lt.usr
		  HAVING  SUM(
		  		(SELECT	COUNT(*)
				  FROM	money.collections_tracker
				  WHERE	usr = lt.usr
				  	AND location in (
				  		(SELECT	id
						  FROM	$descendants )
					)
				) ) = 0
		  	AND (SUM(bl.amount) - COALESCE(SUM((SELECT SUM(amount) FROM money.payment WHERE xact = lt.id)),0)) > ? 
	SQL

	my @l_ids;
	for my $l (@loc) {
		my $sth = money::collections_tracker->db_Main->prepare($SQL);
		$sth->execute(uc($l), $age, uc($l), $amount );
		while (my $row = $sth->fetchrow_hashref) {
			#$row->{usr} = actor::user->retrieve($row->{usr})->to_fieldmapper;
			$client->respond( $row );
		}
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'new_collections',
	api_name	=> 'open-ils.storage.money.collections.users_of_interest',
	stream		=> 1,
	argc		=> 3,
);

sub active_in_collections {
	my $self = shift;
	my $client = shift;
	my $startdate = shift;
	my $enddate = shift;
	my @loc = @_;

	my $mct = money::collections_tracker->table;
	my $mb = money::billing->table;
	my $circ = action::circulation->table;
	my $mg = money::grocery->table;
	my $descendants = "actor.org_unit_descendants((select id from actor.org_unit where shortname = ?))";

	my $SQL = <<"	SQL";
		SELECT	lt.usr,
			MAX(bl.billing_ts) AS last_pertinent_billing,
			MAX(pm.payment_ts) AS last_pertinent_payment
		  FROM	( SELECT id,usr,billing_location AS location FROM money.grocery
		  		UNION ALL
			  SELECT id,usr,circ_lib AS location FROM action.circulation ) AS lt
			JOIN $descendants d ON (lt.location = d.id)
			JOIN money.collections_tracker cl ON (lt.usr = cl.usr)
			LEFT JOIN money.billing bl ON (lt.id = bl.xact)
			LEFT JOIN money.payment pm ON (lt.id = pm.xact)
		  WHERE	cl.location IN ((SELECT id FROM $descendants))
		  	AND (	bl.billing_ts between ? and ?
				OR pm.payment_ts between ? and ? )
		  GROUP BY 1
	SQL

	my @l_ids;
	for my $l (@loc) {
		my $sth = money::collections_tracker->db_Main->prepare($SQL);
		$sth->execute(uc($l), uc($l), $startdate, $enddate, $startdate, $enddate );
		while (my $row = $sth->fetchrow_hashref) {
			$row->{usr} = actor::user->retrieve($row->{usr})->to_fieldmapper;
			$client->respond( $row );
		}
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'active_in_collections',
	api_name	=> 'open-ils.storage.money.collections.users_with_activity',
	stream		=> 1,
	argc		=> 3,
);

1;
