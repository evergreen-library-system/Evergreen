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
__PACKAGE__->columns( Others => qw/id usrid usrname email prefix first_given_name
				second_given_name family_name suffix address
				home_ou gender dob active master_account
				super_user usrgroup passwd/ );

#-------------------------------------------------------------------------------
package actor::org_unit_type;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit_type' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Others => qw/name depth parent can_have_users/);

#-------------------------------------------------------------------------------
package actor::org_unit;
use base qw/actor/;
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
#-------------------------------------------------------------------------------
1;

