package OpenILS::Application::Storage::CDBI::container;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package container;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package container::user_bucket;
use base qw/container/;

container::user_bucket->table( 'container_user_bucket' );
container::user_bucket->columns( All => qw/id owner name/ );

#-------------------------------------------------------------------------------
package container::user_bucket_item;
use base qw/container/;

container::user_bucket->table( 'container_user_bucket_item' );
container::user_bucket->columns( All => qw/id bucket target_user/ );

#-------------------------------------------------------------------------------
package container::copy_bucket;
use base qw/container/;

container::copy_bucket->table( 'container_copy_bucket' );
container::copy_bucket->columns( All => qw/id owner name/ );

#-------------------------------------------------------------------------------
package container::copy_bucket_item;
use base qw/container/;

container::copy_bucket->table( 'container_copy_bucket_item' );
container::copy_bucket->columns( All => qw/id bucket target_copy/ );

#-------------------------------------------------------------------------------
package container::biblio_record_entry_bucket;
use base qw/container/;

container::biblio_record_entry_bucket->table( 'container_biblio_record_entry_bucket' );
container::biblio_record_entry_bucket->columns( All => qw/id owner name/ );

#-------------------------------------------------------------------------------
package container::biblio_record_entry_bucket_item;
use base qw/container/;

container::biblio_record_entry_bucket->table( 'container_biblio_record_entry_bucket_item' );
container::biblio_record_entry_bucket->columns( All => qw/id bucket target_biblio_record_entry/ );

#-------------------------------------------------------------------------------
package container::call_number_bucket;
use base qw/container/;

container::call_number_bucket->table( 'container_call_number_bucket' );
container::call_number_bucket->columns( All => qw/id owner name/ );

#-------------------------------------------------------------------------------
package container::call_number_bucket_item;
use base qw/container/;

container::call_number_bucket->table( 'container_call_number_bucket_item' );
container::call_number_bucket->columns( All => qw/id bucket target_call_number/ );


1;

