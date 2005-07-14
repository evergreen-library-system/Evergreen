package OpenILS::Application::Storage::Publisher::money;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::Utils::Logger qw/:level/;
my $log = 'OpenSRF::Utils::Logger';

sub xact_summary {
	my $self = shift;
	my $client = shift;
	my $xact = shift || '';

	my $sql = <<"	SQL";
		SELECT	balance_owed
		  FROM	money.usr_billable_summary_xact
		  WHERE	transaction = ?
	SQL

	return money::billing->db_Main->selectrow_hashref($sql, {}, "$xact");
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.money.billing.billable_transaction_summary',
	api_level       => 1,
	method          => 'xact_summary',
);

1;
