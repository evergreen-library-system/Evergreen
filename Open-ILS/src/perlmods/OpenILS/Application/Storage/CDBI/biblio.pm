package OpenILS::Application::Storage::CDBI::biblio;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package biblio;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package biblio::record_entry;
use base qw/biblio/;

biblio::record_entry->table( 'biblio_record_entry' );
biblio::record_entry->columns( Essential => qw/id tcn_source tcn_value creator editor
				      create_date edit_date source active
				      deleted marc last_xact_id fingerprint/ );

#-------------------------------------------------------------------------------
package biblio::record_note;
use base qw/biblio/;

biblio::record_note->table( 'biblio_record_note' );
biblio::record_note->columns( Essential => qw/id record value creator
					editor create_date edit_date/ );
#-------------------------------------------------------------------------------

1;

