package OpenILS::Application::Storage::CDBI::metabib;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package metabib;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package metabib::metarecord;
use base qw/metabib/;

metabib::metarecord->table( 'metabib_metarecord' );
metabib::metarecord->columns( Primary => qw/id/ );
metabib::metarecord->columns( Others => qw/fingerprint master_record/ );

#-------------------------------------------------------------------------------
package metabib::title_field_entry;
use base qw/metabib/;

metabib::title_field_entry->table( 'metabib_title_field_entry' );
metabib::title_field_entry->columns( Primary => qw/id/ );
metabib::title_field_entry->columns( Others => qw/field value source/ );


#-------------------------------------------------------------------------------
package metabib::author_field_entry;
use base qw/metabib/;

metabib::author_field_entry->table( 'metabib_author_field_entry' );
metabib::author_field_entry->columns( Primary => qw/id/ );
metabib::author_field_entry->columns( Others => qw/field value source/ );


#-------------------------------------------------------------------------------
package metabib::subject_field_entry;
use base qw/metabib/;

metabib::subject_field_entry->table( 'metabib_subject_field_entry' );
metabib::subject_field_entry->columns( Primary => qw/id/ );
metabib::subject_field_entry->columns( Others => qw/field value source/ );


#-------------------------------------------------------------------------------
package metabib::keyword_field_entry;
use base qw/metabib/;

metabib::keyword_field_entry->table( 'metabib_keyword_field_entry' );
metabib::keyword_field_entry->columns( Primary => qw/id/ );
metabib::keyword_field_entry->columns( Others => qw/field value source/ );

#-------------------------------------------------------------------------------
package metabib::metarecord_source_map;
use base qw/metabib/;

metabib::metarecord_source_map->table( 'metabib_metarecord_source_map' );
metabib::metarecord_source_map->columns( Primary => qw/id/ );
metabib::metarecord_source_map->columns( Others => qw/metarecord source/ );

#-------------------------------------------------------------------------------
package metabib::full_rec;
use base qw/metabib/;

metabib::full_rec->table( 'metabib_full_rec' );
metabib::full_rec->columns( Primary => qw/id/ );
metabib::full_rec->columns( Others => qw/record tag ind1 ind2 subfield value/ );

#-------------------------------------------------------------------------------
package metabib::record_descriptor;
use base qw/metabib/;
#use OpenILS::Application::Storage::CDBI::asset;

metabib::record_descriptor->table( 'metabib_rec_descriptor' );
metabib::record_descriptor->columns( Primary => qw/id/ );
metabib::record_descriptor->columns( Others => qw/record item_type item_form bib_level
					 control_type char_encoding enc_level
					 cat_form pub_status item_lang audience/ );

#-------------------------------------------------------------------------------

1;

