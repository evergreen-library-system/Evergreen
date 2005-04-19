package OpenILS::Application::Storage::CDBI::actor;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package actor;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package actor::user;
use base qw/actor/;

__PACKAGE__->table( 'actor_usr' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/usrid usrname email first_given_name
				second_given_name family_name billing_address
				claims_returned_count home_ou gender dob
				active master_account ident_type ident_value
				super_user usrgroup passwd card last_xact_id
				standing profile prefix suffix alert_message
				day_phone evening_phone other_phone mailing_address/ );

#-------------------------------------------------------------------------------
package actor::profile;
use base qw/actor/;

__PACKAGE__->table( 'actor_profile' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/name/);

#-------------------------------------------------------------------------------
package actor::org_unit_type;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit_type' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/name depth parent can_have_vols can_have_users/);

#-------------------------------------------------------------------------------
package actor::org_unit;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/parent_ou ou_type address shortname name/);

#-------------------------------------------------------------------------------
package actor::stat_cat;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owner name opac_visible/ );

#-------------------------------------------------------------------------------
package actor::stat_cat_entry;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat_entry' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owner value/ );

#-------------------------------------------------------------------------------
package actor::stat_cat_entry_user_map;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat_entry_usr_map' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/stat_cat_entry target_user/ );

#-------------------------------------------------------------------------------
package actor::card;
use base qw/actor/;

__PACKAGE__->table( 'actor_card' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/usr barcode active/ );

#-------------------------------------------------------------------------------
package actor::user_access_entry;
use base qw/actor/;
#-------------------------------------------------------------------------------
package actor::perm_group;
use base qw/actor/;
#-------------------------------------------------------------------------------
package actor::permission;
use base qw/actor/;
#-------------------------------------------------------------------------------
package actor::perm_group_permission_map;
use base qw/actor/;
#-------------------------------------------------------------------------------
package actor::perm_group_user_map;
use base qw/actor/;
#-------------------------------------------------------------------------------
package actor::user_address;
use base qw/actor/;

__PACKAGE__->table( 'actor_card' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/valid address_type usr street1 street2
				      city county state country post_code/ );

#-------------------------------------------------------------------------------
package actor::org_address;
use base qw/actor/;

__PACKAGE__->table( 'actor_card' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/valid address_type usr street1 street2
				      city county state country post_code/ );

#-------------------------------------------------------------------------------
package actor::profile;
use base qw/actor/;

__PACKAGE__->table( 'actor_card' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/name/ );

#-------------------------------------------------------------------------------
1;

