package OpenILS::Application::Storage::CDBI::booking;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package booking;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package booking::reservation;
use base qw/booking/;
__PACKAGE__->table('booking_reservation');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start usr current_copy circ_lib
				     fine_amount max_fine fine_interval xact_finish 
				     capture_staff pickup_lib request_time start_time end_time
                     capture_time cancel_time pickup_time return_time
                     booking_interval target_resource_type target_resource
                     current_resource request_lib/);

#-------------------------------------------------------------------------------

1;

