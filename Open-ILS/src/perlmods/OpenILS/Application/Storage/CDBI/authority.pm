package OpenILS::Application::Storage::CDBI::authority;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package authority;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package authority::record_entry;
use base qw/authority/;

authority::record_entry->table( 'authority_record_entry' );
authority::record_entry->columns( Primary => qw/id/ );
authority::record_entry->columns( Essential => qw/arn_source arn_value creator editor
				      create_date edit_date source active
				      deleted marc last_xact_id/ );

#-------------------------------------------------------------------------------
package authority::record_note;
use base qw/authority/;

authority::record_note->table( 'authority_record_note' );
authority::record_note->columns( Primary => qw/id/ );
authority::record_note->columns( Essential => qw/record value creator
					editor create_date edit_date/ );
#-------------------------------------------------------------------------------
package authority::full_rec;
use base qw/authority/;

authority::full_rec->table( 'authority_full_rec' );
authority::full_rec->columns( Primary => qw/id/ );
authority::full_rec->columns( Essential => qw/record tag ind1 ind2 subfield value/ );

#-------------------------------------------------------------------------------
package authority::record_descriptor;
use base qw/authority/;
#use OpenILS::Application::Storage::CDBI::asset;

authority::record_descriptor->table( 'authority_rec_descriptor' );
authority::record_descriptor->columns( Primary => qw/id/ );
authority::record_descriptor->columns( Essential => qw/record record_status
						    char_encoding/ );

#-------------------------------------------------------------------------------


1;

