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
__PACKAGE__->columns( Others => qw/record label/ );

#-------------------------------------------------------------------------------
package asset::copy;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Others => qw/call_number barcode/ );

#-------------------------------------------------------------------------------
package asset::copy_metadata;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy_metadata' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Others => qw/checkout_status circulating_location hold_radius/ );

#-------------------------------------------------------------------------------
1;

