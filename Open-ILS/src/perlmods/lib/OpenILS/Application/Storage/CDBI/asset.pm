package OpenILS::Application::Storage::CDBI::asset;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package asset;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package asset::copy_location;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy_location' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/name owning_lib holdable hold_verify opac_visible circulate label_prefix label_suffix/ );

#-------------------------------------------------------------------------------
package asset::copy_location_order;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy_location_order' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/location org position/ );

#-------------------------------------------------------------------------------
package asset::call_number_suffix;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number_suffix' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owning_lib label label_sortkey/ );

#-------------------------------------------------------------------------------
package asset::call_number_prefix;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number_prefix' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owning_lib label label_sortkey/ );

#-------------------------------------------------------------------------------
package asset::call_number_class;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number_class' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/name normalizer field/ );

#-------------------------------------------------------------------------------
package asset::call_number;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/record label creator create_date editor prefix suffix
				   edit_date record label owning_lib deleted label_class label_sortkey/ );

#-------------------------------------------------------------------------------
package asset::call_number_note;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number_note' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/call_number title creator create_date value pub/ );

#-------------------------------------------------------------------------------
package asset::copy;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/call_number barcode creator create_date editor
				   edit_date copy_number status loan_duration circ_lib dummy_isbn
				   fine_level circulate deposit price ref opac_visible
				   circ_as_type circ_modifier deposit_amount location mint_condition
				   holdable dummy_title dummy_author deleted alert_message
				   age_protect floating cost status_changed_time/ );

#-------------------------------------------------------------------------------
package asset::copy_part_map;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy_part_map' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/target_copy part/);

#-------------------------------------------------------------------------------
package asset::stat_cat;
use base qw/asset/;

__PACKAGE__->table( 'asset_stat_cat' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owner name opac_visible required/ );

#-------------------------------------------------------------------------------
package asset::stat_cat_entry;
use base qw/asset/;

__PACKAGE__->table( 'asset_stat_cat_entry' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/stat_cat owner value/ );

#-------------------------------------------------------------------------------
package asset::stat_cat_entry_copy_map;
use base qw/asset/;

__PACKAGE__->table( 'asset_stat_cat_entry_copy_map' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/stat_cat stat_cat_entry owning_copy/ );

#-------------------------------------------------------------------------------
package asset::copy_note;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy_note' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owning_copy title creator create_date value pub/ );

#-------------------------------------------------------------------------------


1;

