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
                      create_date edit_date source active quality owner share_depth
                      deleted marc last_xact_id fingerprint/ );

#-------------------------------------------------------------------------------
package biblio::record_note;
use base qw/biblio/;

biblio::record_note->table( 'biblio_record_note' );
biblio::record_note->columns( Essential => qw/id record value creator
                    editor create_date edit_date/ );
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
package biblio::peer_type;
use base qw/biblio/;

biblio::peer_type->table( 'biblio_peer_type' );
biblio::peer_type->columns( Essential => qw/id name/ );
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
package biblio::peer_bib_copy_map;
use base qw/biblio/;

biblio::peer_bib_copy_map->table( 'biblio_peer_bib_copy_map' );
biblio::peer_bib_copy_map->columns( Essential => qw/id peer_type peer_record target_copy/ );
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
package biblio::monograph_part;
use base qw/biblio/;

biblio::monograph_part->table( 'biblio_monograph_part' );
biblio::monograph_part->columns( Essential => qw/id record label label_sortkey deleted creator create_date editor edit_date/ );
#-------------------------------------------------------------------------------

1;

