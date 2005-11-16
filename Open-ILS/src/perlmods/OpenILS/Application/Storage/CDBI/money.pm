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
__PACKAGE__->columns(Essential => qw/xact_start usr/);
__PACKAGE__->columns(Others => qw/xact_finish/);
#-------------------------------------------------------------------------------

package money::user_summary;
use base qw/money/;
__PACKAGE__->table('money_user_summary');
__PACKAGE__->columns(Primary => 'usr');
__PACKAGE__->columns(Essential => qw/total_paid total_owed balance_owed/);
#-------------------------------------------------------------------------------

package money::user_circulation_summary;
use base qw/money/;
__PACKAGE__->table('money_user_circulation_summary');
__PACKAGE__->columns(Primary => 'usr');
__PACKAGE__->columns(Essential => qw/total_paid total_owed balance_owed/);
#-------------------------------------------------------------------------------

package money::billable_transaction_summary;
use base qw/money/;
__PACKAGE__->table('money_billable_transaction_summary');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start usr xact_finish total_paid
				     last_payment_ts total_owed last_billing_ts
				     balance_owed xact_type last_billing_note last_billing_type
				     last_payment_note last_payment_type/);
#-------------------------------------------------------------------------------

package money::billing;
use base qw/money/;
__PACKAGE__->table('money_billing');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount billing_ts note voided/);
#-------------------------------------------------------------------------------

package money::payment;
use base qw/money/;
__PACKAGE__->table('money_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts payment_type/);
__PACKAGE__->columns(Others => qw/note/);
#-------------------------------------------------------------------------------

package money::cash_payment;
use base qw/money/;
__PACKAGE__->table('money_cash_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts cash_drawer accepting_usr amount_collected/);
__PACKAGE__->columns(Others => qw/note/);
#-------------------------------------------------------------------------------

package money::check_payment;
use base qw/money/;
__PACKAGE__->table('money_check_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts cash_drawer check_number accepting_usr amount_collected/);
__PACKAGE__->columns(Others => qw/note/);
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
__PACKAGE__->table('money_forgive_payment');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact amount payment_ts accepting_usr amount_collected/);
__PACKAGE__->columns(Others => qw/note/);
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

