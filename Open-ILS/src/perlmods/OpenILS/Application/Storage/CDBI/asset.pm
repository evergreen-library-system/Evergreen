package OpenILS::Application::Storage::CDBI::asset;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package asset;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package asset::call_number;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Others => qw/record label creator create_date editor edit_date record label owning_lib/ );

#-------------------------------------------------------------------------------
package asset::call_number_note;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Others => qw/owning_call_number title creator create_date value/ );

#-------------------------------------------------------------------------------
package asset::copy;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Others => qw/call_number barcode creator create_date editor
				   edit_date copy_number status home_lib loan_duration
				   fine_level circulate deposit price ref opac_visible
				   genre audience shelving_loc deposit_amount/ );

#-------------------------------------------------------------------------------
package asset::copy_note;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy_note' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Others => qw/owning_copy title creator create_date value/ );

#-------------------------------------------------------------------------------


1;

