#-------------------------------------------------------------------------------
package biblio;
use base qw/OpenILS::App::Storage::CDBI/;
#-------------------------------------------------------------------------------
package biblio::record_entry;
use base qw/biblio/;
#-------------------------------------------------------------------------------
package biblio::record_node;
use base qw/biblio/;
#-------------------------------------------------------------------------------
package biblio::record_note;
use base qw/biblio/;

1;

