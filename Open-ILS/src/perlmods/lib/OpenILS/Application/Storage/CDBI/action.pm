package OpenILS::Application::Storage::CDBI::action;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package action;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package action::in_house_use;
use base qw/action/;
__PACKAGE__->table('action_in_house_use');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/item staff org_unit use_time/);
#-------------------------------------------------------------------------------

package action::non_cat_in_house_use;
use base qw/action/;
__PACKAGE__->table('action_non_cat_in_house_use');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/item_type staff org_unit use_time/);
#-------------------------------------------------------------------------------

package action::non_cataloged_circulation;
use base qw/action/;
__PACKAGE__->table('action_non_cataloged_circulation');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/patron staff circ_lib item_type circ_time/);
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
__PACKAGE__->columns(Essential => qw/response_group_id usr survey question
				     answer answer_date effective_date/);
#-------------------------------------------------------------------------------

package action::circulation;
use base qw/action/;
__PACKAGE__->table('action_circulation');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start usr target_copy circ_lib
				     duration duration_rule renewal_remaining grace_period
				     recurring_fine_rule recurring_fine stop_fines
				     max_fine max_fine_rule fine_interval
				     stop_fines xact_finish due_date opac_renewal
				     checkin_staff circ_staff circ_lib checkin_lib
				     stop_fines_time checkin_time desk_renewal
				     phone_renewal create_time copy_location/);

#-------------------------------------------------------------------------------

package action::open_circulation;
use base qw/action/;
__PACKAGE__->table('action_open_circulation');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start usr target_copy circ_lib
				     duration duration_rule renewal_remaining grace_period
				     recurring_fine_rule recurring_fine stop_fines
				     max_fine max_fine_rule fine_interval
				     stop_fines xact_finish due_date opac_renewal
				     checkin_staff circ_staff circ_lib checkin_lib
				     stop_fines_time checkin_time desk_renewal
				     phone_renewal/);

#-------------------------------------------------------------------------------

package action::hold_request;
use base qw/action/;
__PACKAGE__->table('action_hold_request');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/request_time capture_time fulfillment_time
				     prev_check_time expire_time requestor usr cancel_cause
				     hold_type holdable_formats target cancel_time shelf_time
				     phone_notify email_notify sms_notify sms_carrier selection_depth cancel_note
				     pickup_lib current_copy request_lib frozen thaw_date mint_condition
				     fulfillment_staff fulfillment_lib selection_ou cut_in_line
					 shelf_expire_time current_shelf_lib/);

#-------------------------------------------------------------------------------

package action::hold_notification;
use base qw/action/;
__PACKAGE__->table('action_hold_notification');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/hold method notify_time note notify_staff/);

#-------------------------------------------------------------------------------

package action::hold_copy_map;
use base qw/action/;
__PACKAGE__->table('action_hold_copy_map');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/hold target_copy/);

#-------------------------------------------------------------------------------

package action::hold_transit_copy;
use base qw/action/;
__PACKAGE__->table('action_hold_transit_copy');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/source dest persistant_transfer target_copy
				     source_send_time dest_recv_time prev_hop prev_dest
				     copy_status hold/);

#-------------------------------------------------------------------------------

package action::reservation_transit_copy;
use base qw/action/;
__PACKAGE__->table('action_reservation_transit_copy');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/source dest persistant_transfer target_copy
				     source_send_time dest_recv_time prev_hop prev_dest
				     copy_status reservation/);

#-------------------------------------------------------------------------------

package action::transit_copy;
use base qw/action/;
__PACKAGE__->table('action_transit_copy');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/source dest persistant_transfer target_copy
				     source_send_time dest_recv_time prev_hop prev_dest
				     copy_status/);

#-------------------------------------------------------------------------------

package action::unfulfilled_hold_list;
use base qw/action/;
__PACKAGE__->table('action_unfulfilled_hold_list');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/hold current_copy circ_lib fail_time /);

#-------------------------------------------------------------------------------

1;

