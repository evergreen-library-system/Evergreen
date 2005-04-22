package OpenILS::Application::Storage::CDBI::action;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package action;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package action::survey;
use base qw/action/;
__PACKAGE__->table('action_survey');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name description owner start_date end_date usr_summary opac required/);
#-------------------------------------------------------------------------------

package action::survey_question;
use base qw/action/;
__PACKAGE__->table('action_survey_question');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/survey question/);
#-------------------------------------------------------------------------------


package action::survey_answer;
use base qw/action/;
__PACKAGE__->table('action_survey_answer');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/question answer/);
#-------------------------------------------------------------------------------

package action::survey_response;
use base qw/action/;
__PACKAGE__->table('action_survey_response');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/usr survey question answer answer_date effective_date/);
#-------------------------------------------------------------------------------

package action::circulation;
use base qw/action/;
__PACKAGE__->table('action_circulation');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start usr target_copy circ_lib
				     duration renewal_remaining fine_amount
				     max_fines fine_interval/);
__PACKAGE__->columns(Others => qw/note stop_fines xact_finish/);

#-------------------------------------------------------------------------------

1;

