package OpenILS::Application::Storage::CDBI::serial;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package serial;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package serial::subscription;
use base qw/serial/;

__PACKAGE__->table( 'serial_subscription' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/record_entry start_date end_date
				   expected_date_offset owning_lib/ );

#-------------------------------------------------------------------------------
package serial::issuance;
use base qw/serial/;

__PACKAGE__->table( 'serial_issuance' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/creator editor create_date edit_date
                                      subscription label date_published
                                      holding_code holding_type holding_link_id/ );

#-------------------------------------------------------------------------------
package serial::item;
use base qw/serial/;

__PACKAGE__->table( 'serial_item' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/creator editor create_date edit_date
                                      issuance stream unit uri date_expected
                                      date_received/ );

#-------------------------------------------------------------------------------
package serial::unit;
use base qw/serial/;

__PACKAGE__->table( 'serial_unit' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/call_number barcode creator create_date editor
				   edit_date copy_number status loan_duration circ_lib
				   fine_level circulate deposit price ref opac_visible dummy_isbn
				   circ_as_type circ_modifier deposit_amount location mint_condition
				   holdable dummy_title dummy_author deleted alert_message label
				   age_protect floating label_sort_key contents/ );

1;

