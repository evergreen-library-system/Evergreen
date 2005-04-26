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
__PACKAGE__->columns(Essential => qw/name description owner start_date
				     end_date usr_summary opac poll required/);
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
				     duration duration_rule renewal_remaining
				     recuring_fine_rule recuring_fine stop_fines
				     max_fine max_fine_rule fine_interval
				     stop_fines xact_finish/);

#-------------------------------------------------------------------------------

1;

