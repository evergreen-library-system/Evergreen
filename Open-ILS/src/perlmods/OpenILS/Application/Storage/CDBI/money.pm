package OpenILS::Application::Storage::CDBI::money;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package money;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package money::billable_transaction;
use base qw/money/;
__PACKAGE__->table('money_billable_xact');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start xact_finish usr/);
#-------------------------------------------------------------------------------

package money::billing;
use base qw/money/;
__PACKAGE__->table('money_billing');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount billing_ts note/);
#-------------------------------------------------------------------------------

package money::payment;
use base qw/money/;
__PACKAGE__->table('money_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => "split_part(tableoid2name(tableoid),'.',2) as payment_type", qw/xact amount payment_ts note/);
#-------------------------------------------------------------------------------

package money::cash_payment;
use base qw/money/;
__PACKAGE__->table('money_cash_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts note cash_drawer accepting_usr amount_collected/);
#-------------------------------------------------------------------------------

package money::check_payment;
use base qw/money/;
__PACKAGE__->table('money_check_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts note cash_drawer check_number accepting_usr amount_collected/);
#-------------------------------------------------------------------------------

package money::credit_card_payment;
use base qw/money/;
__PACKAGE__->table('money_credit_card_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts cash_drawer
				     accepting_usr amount_collected cc_type
				     cc_number expire_month expire_year
				     approval_code/);
__PACKAGE__->columns(Others => 'note');
#-------------------------------------------------------------------------------

package money::forgive_payment;
use base qw/money/;
__PACKAGE__->table('money_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts note accepting_usr amount_collected/);
#-------------------------------------------------------------------------------

package money::work_payment;
use base qw/money::forgive_payment/;
__PACKAGE__->table('money_work_payment');
#-------------------------------------------------------------------------------

package money::credit_payment;
use base qw/money::forgive_payment/;
__PACKAGE__->table('money_credit_payment');

#-------------------------------------------------------------------------------

1;

