package OpenILS::Application::Storage::CDBI::asset;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package asset;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package asset::call_number;
use base qw/asset/;

__PACKAGE__->table( 'asset_call_number' );
__PACKAGE__->columns( All => qw/id record label/ );

#-------------------------------------------------------------------------------
package asset::copy;
use base qw/asset/;

__PACKAGE__->table( 'asset_copy' );
__PACKAGE__->columns( All => qw/id call_number barcode/ );

#-------------------------------------------------------------------------------
1;

