package OpenILS::Application::Storage::CDBI::booking;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package booking;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package booking::resource_type;
use base qw/booking/;
__PACKAGE__->table('booking_resource_type');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name fine_interval fine_amount
                     max_fine owner catalog_item record transferable elbow_room/);

#-------------------------------------------------------------------------------

package booking::resource;
use base qw/booking/;
__PACKAGE__->table('booking_resource');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/owner type overbook barcode deposit
                     deposit_amount user_fee/);

#-------------------------------------------------------------------------------

package booking::reservation;
use base qw/booking/;
__PACKAGE__->table('booking_reservation');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/xact_start usr current_resource
                     fine_amount max_fine fine_interval xact_finish 
                     capture_staff pickup_lib request_time start_time end_time
                     capture_time cancel_time pickup_time return_time
                     booking_interval target_resource_type target_resource
                     current_resource request_lib/);

#-------------------------------------------------------------------------------

package booking::resource_attr_map;
use base qw/booking/;
__PACKAGE__->table('booking_resource_attr_map');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/resource resource_attr value/);

#-------------------------------------------------------------------------------

package booking::reservation_attr_value_map;
use base qw/booking/;
__PACKAGE__->table('booking_reservation_attr_value_map');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/reservation attr_value/);

#-------------------------------------------------------------------------------

1;

