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
biblio::record_entry->columns( Primary		=> 'id' );
biblio::record_entry->columns( Essential	=> qw/tcn_source tcn_value creator editor
						      create_date edit_date source active
						      deleted last_xact_id/ );
biblio::record_entry->columns( Others		=> qw/fingerprint/ );

#-------------------------------------------------------------------------------
#package biblio::record_node::subnode;
#sub _load {
#	my $intra_doc_id = shift;
#	my $owner_doc = shift()->owner_doc;
#	return (biblio::record_node->search(
#			owner_doc	=> $owner_doc,
#			intra_doc_id	=> $intra_doc_id
#		)
#	)[0];
#}
#
#package biblio::record_node;
#use base qw/biblio/;
#
#biblio::record_node->table( 'biblio_record_data' );
#biblio::record_node->columns( All => qw/id owner_doc intra_doc_id
#					parent_node node_type
#					namespace_uri name value last_xact_id/ );
#
#biblio::record_node->has_a(
#	parent_node	=> 'biblio::record_node::subnode',
#	inflate		=> sub {
#				return biblio::record_node::subnode::_load(@_)
#			},
#);


#-------------------------------------------------------------------------------
package biblio::record_marc;
use base qw/biblio/;

biblio::record_marc->table( 'biblio_record_marc' );
biblio::record_marc->columns( All => qw/id marc last_xact_id/ );
#biblio::record_marc->columns( Stringify => qw/marc/ );
#biblio::record_marc->is_a( id => qw/biblio::record_entry/ );

#-------------------------------------------------------------------------------
#package biblio::record_mods;
#use base qw/biblio/;

#biblio::record_mods->table( 'biblio_record_mods' );
#biblio::record_mods->columns( All => qw/id mods/ );
#biblio::record_mods->columns( Stringify => qw/mods/ );
#biblio::record_mods->is_a( id => qw/biblio::record_entry/ );

#-------------------------------------------------------------------------------
package biblio::record_note;
use base qw/biblio/;

biblio::record_note->table( 'biblio_record_note' );
biblio::record_note->columns( All => qw/id record value creator
					editor create_date edit_date/ );
#biblio::record_note->columns( Stringify => qw/value/ );
#biblio::record_note->is_a( record => qw/biblio::record_entry/ );

#-------------------------------------------------------------------------------

1;

