package OpenILS::Application::Storage::CDBI;
use vars qw/@ISA/;
use Class::DBI;
use base qw/Class::DBI/;

our $VERSION = 1;

use OpenILS::Application::Storage::CDBI::actor;
use OpenILS::Application::Storage::CDBI::asset;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Application::Storage::CDBI::metabib;


#-------------------------------------------------------------------------------
asset::copy->has_a( call_number => 'asset::call_number' );
#-------------------------------------------------------------------------------
asset::call_number->has_a( record => 'biblio::record_entry' );
asset::call_number->has_many( copies => 'asset::copy' );
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
biblio::record_note->has_a( record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------
biblio::record_entry->has_many( notes => 'biblio::record_note' );
biblio::record_entry->has_many( nodes => 'biblio::record_node', { order_by => 'intra_doc_id' } );
biblio::record_entry->has_many( call_numbers => 'asset::call_number' );
biblio::record_entry->has_a( metarecord => 'metabib::metarecord' );

# should we have just one field entry per class for each record???? (xslt vs xpath)
#biblio::record_entry->has_a( title_field_entries => 'metabib::title_field_entry' );
#biblio::record_entry->has_a( author_field_entries => 'metabib::author_field_entry' );
#biblio::record_entry->has_a( subject_field_entries => 'metabib::subject_field_entry' );
#biblio::record_entry->has_a( keyword_field_entries => 'metabib::keyword_field_entry' );
#-------------------------------------------------------------------------------
biblio::record_node->has_a( owner_doc => 'biblio::record_entry' );
#biblio::record_node->has_a(
#	parent_node	=> 'biblio::record_node::subnode',
#	inflate		=> sub { return biblio::record_node::subnode::_load(@_) }
#);
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#metabib::metarecord->has_a( master_record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------
#metabib::title_field_entry->has_a( field => 'config::metabib_field_map' );
#-------------------------------------------------------------------------------
#metabib::author_field_entry->has_a( field => 'config::metabib_field_map' );
#-------------------------------------------------------------------------------
#metabib::subject_field_entry->has_a( field => 'config::metabib_field_map' );
#-------------------------------------------------------------------------------
#metabib::keyword_field_entry->has_a( field => 'config::metabib_field_map' );
#-------------------------------------------------------------------------------


# should we have just one field entry per class for each record???? (xslt vs xpath)
#metabib::title_field_entry_source_map->has_a( field_entry => 'metabib::title_field_entry' );
#metabib::title_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------
#metabib::subject_field_entry_source_map->has_a( field_entry => 'metabib::subject_field_entry' );
#metabib::subject_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------
#metabib::author_field_entry_source_map->has_a( field_entry => 'metabib::author_field_entry' );
#metabib::author_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------
#metabib::keyword_field_entry_source_map->has_a( field_entry => 'metabib::keyword_field_entry' );
#metabib::keyword_field_entry_source_map->has_a( source_record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------


1;
