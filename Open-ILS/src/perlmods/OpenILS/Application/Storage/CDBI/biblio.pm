package OpenILS::Application::Storage::CDBI::biblio;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package biblio;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package biblio::record_entry;
use base qw/biblio/;
#use OpenILS::Application::Storage::CDBI::asset;

biblio::record_entry->table( 'biblio_record_entry' );
biblio::record_entry->columns( All => qw/id tcn_source tcn_value metarecord
					 creator editor create_date edit_date
					 source active deleted source/ );

#-------------------------------------------------------------------------------
package biblio::record_node::subnode;
sub _load {
	my $intra_doc_id = shift;
	my $owner_doc = shift()->owner_doc;
	return (biblio::record_node->search(
			owner_doc	=> $owner_doc,
			intra_doc_id	=> $intra_doc_id
		)
	)[0];
}

package biblio::record_node;
use base qw/biblio/;

biblio::record_node->table( 'biblio_record_data' );
biblio::record_node->columns( All => qw/id owner_doc intra_doc_id
					parent_node node_type
					namespace_uri name value/ );

#biblio::record_node->has_a(
#	parent_node	=> 'biblio::record_node::subnode',
#	inflate		=> sub {
#				return biblio::record_node::subnode::_load(@_)
#			},
#);


#-------------------------------------------------------------------------------
package biblio::record_note;
use base qw/biblio/;

biblio::record_note->table( 'biblio_record_note' );
biblio::record_note->columns( All => qw/id record value creator
					editor create_date edit_date/ );
biblio::record_note->columns( Stringify => qw/value/ );

#-------------------------------------------------------------------------------

1;

