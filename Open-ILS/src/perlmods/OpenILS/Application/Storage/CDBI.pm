package OpenILS::Application::Storage::CDBI;
use vars qw/@ISA/;
use Class::DBI;
use base qw/Class::DBI/;

our $VERSION = 1;

use OpenILS::Application::Storage::CDBI::actor;
use OpenILS::Application::Storage::CDBI::asset;
use OpenILS::Application::Storage::CDBI::biblio;


#-------------------------------------------------------------------------------
asset::copy->has_a( call_number => 'asset::call_number' );
#-------------------------------------------------------------------------------
asset::call_number->has_a( record => 'biblio::record_entry' );
asset::call_number->has_many( copies => 'asset::copy' );
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
biblio::record_note->has_a( record => 'biblio::record_entry' );
#-------------------------------------------------------------------------------
biblio::record_entry->might_have( note => 'biblio::record_note' );
biblio::record_entry->has_many( nodes => 'biblio::record_node' );
biblio::record_entry->has_many( call_numbers => 'asset::call_number' );
#biblio::record_entry->has_a( metarecord => 'metabib::metarecord' );
#biblio::record_entry->has_many( field_entries => 'metabib::field_entry' );
#-------------------------------------------------------------------------------
biblio::record_node->has_a( owner_doc => 'biblio::record_entry' );
biblio::record_node->has_a( parent_node     => 'biblio::record_node::subnode',
			    inflate         => sub { return biblio::record_node::subnode::_load(@_) });
#-------------------------------------------------------------------------------


1;
