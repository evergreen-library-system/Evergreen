package OpenILS::Application::Storage::CDBI::config;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package config;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package config::bib_source;
use base qw/config/;
__PACKAGE__->table('config_bib_source');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/quality source/);
#-------------------------------------------------------------------------------

package config::metabib_field;
use base qw/config/;
__PACKAGE__->table('config_metabib_field');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/field_class name xpath/);
#-------------------------------------------------------------------------------

package config::identification_type;
use base qw/config/;
__PACKAGE__->table('config_identifaction_type');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name/);
#-------------------------------------------------------------------------------



1;

