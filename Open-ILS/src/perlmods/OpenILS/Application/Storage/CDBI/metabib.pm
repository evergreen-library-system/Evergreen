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
metabib::title_field_entry->columns( Others => qw/field value/ );


#-------------------------------------------------------------------------------
package metabib::author_field_entry;
use base qw/metabib/;

metabib::author_field_entry->table( 'metabib_author_field_entry' );
metabib::author_field_entry->columns( Primary => qw/id/ );
metabib::author_field_entry->columns( Others => qw/field value/ );


#-------------------------------------------------------------------------------
package metabib::subject_field_entry;
use base qw/metabib/;

metabib::subject_field_entry->table( 'metabib_subject_field_entry' );
metabib::subject_field_entry->columns( Primary => qw/id/ );
metabib::subject_field_entry->columns( Others => qw/field value/ );


#-------------------------------------------------------------------------------
package metabib::keyword_field_entry;
use base qw/metabib/;

metabib::keyword_field_entry->table( 'metabib_keyword_field_entry' );
metabib::keyword_field_entry->columns( Primary => qw/id/ );
metabib::keyword_field_entry->columns( Others => qw/field value/ );

#-------------------------------------------------------------------------------
package metabib::title_field_entry_source_map;
use base qw/metabib/;

metabib::title_field_entry_source_map->table( 'metabib_title_field_entry_source_map' );
metabib::title_field_entry_source_map->columns( Primary => qw/id/ );
metabib::title_field_entry_source_map->columns( Others => qw/field_entry source_record/ );

#-------------------------------------------------------------------------------
package metabib::author_field_entry_source_map;
use base qw/metabib/;

metabib::author_field_entry_source_map->table( 'metabib_author_field_entry_source_map' );
metabib::author_field_entry_source_map->columns( Primary => qw/id/ );
metabib::author_field_entry_source_map->columns( Others => qw/field_entry source_record/ );

#-------------------------------------------------------------------------------
package metabib::subject_field_entry_source_map;
use base qw/metabib/;

metabib::subject_field_entry_source_map->table( 'metabib_subject_field_entry_source_map' );
metabib::subject_field_entry_source_map->columns( Primary => qw/id/ );
metabib::subject_field_entry_source_map->columns( Others => qw/field_entry source_record/ );

#-------------------------------------------------------------------------------
package metabib::keyword_field_entry_source_map;
use base qw/metabib/;

metabib::keyword_field_entry_source_map->table( 'metabib_keyword_field_entry_source_map' );
metabib::keyword_field_entry_source_map->columns( Primary => qw/id/ );
metabib::keyword_field_entry_source_map->columns( Others => qw/field_entry source_record/ );

#-------------------------------------------------------------------------------
1;

