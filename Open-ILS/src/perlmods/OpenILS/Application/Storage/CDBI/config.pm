package OpenILS::Application::Storage::CDBI::config;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package config;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------

package config::non_cataloged_type;
use base qw/config/;
__PACKAGE__->table('config_non_cataloged_type');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/owning_lib name circ_duration in_house/);
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
__PACKAGE__->columns(Essential => qw/quality source transcendant/);
#-------------------------------------------------------------------------------

package config::metabib_field;
use base qw/config/;
__PACKAGE__->table('config_metabib_field');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/field_class name xpath wieght/);
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
__PACKAGE__->columns(Essential => qw/name extended normal shrt max_renewals/);
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
__PACKAGE__->columns(Essential => qw/name high normal low recurance_interval/);
#-------------------------------------------------------------------------------

package config::rules::age_hold_protect;
use base qw/config/;
__PACKAGE__->table('config_rule_age_hold_protect');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name age prox/);
#-------------------------------------------------------------------------------

package config::copy_status;
use base qw/config/;
__PACKAGE__->table('config_copy_status');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name holdable/);
#-------------------------------------------------------------------------------

package config::net_access_level;
use base qw/config/;
__PACKAGE__->table('config_net_access_level');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(Essential => qw/name/);
#-------------------------------------------------------------------------------

package config::audience_map;
use base qw/config/;
__PACKAGE__->table('config_audience_map');
__PACKAGE__->columns(Primary => 'code');
__PACKAGE__->columns(Essential => qw/value description/);
#-------------------------------------------------------------------------------

package config::lit_form_map;
use base qw/config/;
__PACKAGE__->table('config_lit_form_map');
__PACKAGE__->columns(Primary => 'code');
__PACKAGE__->columns(Essential => qw/value description/);
#-------------------------------------------------------------------------------

package config::item_form_map;
use base qw/config/;
__PACKAGE__->table('config_lit_form_map');
__PACKAGE__->columns(Primary => 'code');
__PACKAGE__->columns(Essential => qw/value/);
#-------------------------------------------------------------------------------

package config::item_type_map;
use base qw/config/;
__PACKAGE__->table('config_lit_form_map');
__PACKAGE__->columns(Primary => 'code');
__PACKAGE__->columns(Essential => qw/value/);
#-------------------------------------------------------------------------------

package config::language_map;
use base qw/config/;
__PACKAGE__->table('config_language_map');
__PACKAGE__->columns(Primary => 'code');
__PACKAGE__->columns(Essential => qw/value/);
#-------------------------------------------------------------------------------


1;

