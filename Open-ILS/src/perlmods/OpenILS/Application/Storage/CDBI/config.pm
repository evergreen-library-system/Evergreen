package OpenILS::Application::Storage::CDBI::config;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package config;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package config::standing;
use base qw/config/;
__PACKAGE__->table('config_standing');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/value/);
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

package config::rules::circ_duration;
use base qw/config/;
__PACKAGE__->table('config_rule_circ_duration');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name extended normal short max_renewals/);
#-------------------------------------------------------------------------------

package config::rules::max_fine;
use base qw/config/;
__PACKAGE__->table('config_rule_max_fine');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name amount/);
#-------------------------------------------------------------------------------

package config::rules::recuring_fine;
use base qw/config/;
__PACKAGE__->table('config_rule_recuring_fine');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name high normal low/);
#-------------------------------------------------------------------------------

package config::rules::age_hold_protect;
use base qw/config/;
__PACKAGE__->table('config_rule_age_hold_protect');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name age radius/);
#-------------------------------------------------------------------------------


1;

