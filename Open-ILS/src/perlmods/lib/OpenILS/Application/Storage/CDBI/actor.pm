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
__PACKAGE__->columns( Essential => qw/usrname email first_given_name
				second_given_name family_name billing_address
				claims_returned_count home_ou dob deleted juvenile
				active master_account ident_type ident_value
				ident_type2 ident_value2 net_access_level alias
				photo_url create_date expire_date credit_forward_balance
				super_user usrgroup passwd card last_xact_id
				standing barred profile prefix suffix alert_message
				day_phone evening_phone other_phone mailing_address
				claims_never_checked_out_count last_update_time/ );

#-------------------------------------------------------------------------------
package actor::usr_org_unit_opt_in;
use base qw/actor/;
__PACKAGE__->table( 'actor_usr_org_unit_opt_in' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/org_unit usr staff opt_in_ts opt_in_ws/ );

#-------------------------------------------------------------------------------
package actor::org_unit_proximity;
use base qw/actor/;
__PACKAGE__->table( 'actor_org_unit_proximity' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/from_org to_org prox/ );

#-------------------------------------------------------------------------------
package actor::usr_note;
use base qw/actor/;

__PACKAGE__->table( 'actor_usr_note' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/usr title creator create_date value pub/ );

#-------------------------------------------------------------------------------
package actor::workstation;
use base qw/actor/;

__PACKAGE__->table( 'actor_workstation' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/name owning_lib/);

#-------------------------------------------------------------------------------
package actor::user_standing_penalty;
use base qw/actor/;

__PACKAGE__->table( 'actor_user_standing_penalty' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/usr penalty_type/);

#-------------------------------------------------------------------------------
package actor::user_setting;
use base qw/actor/;

__PACKAGE__->table( 'actor_user_setting' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/usr name value/);

#-------------------------------------------------------------------------------
package actor::org_unit_type;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit_type' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/name opac_label depth parent can_have_vols can_have_users/);

#-------------------------------------------------------------------------------
package actor::org_unit;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/parent_ou ou_type mailing_address billing_address
				ill_address holds_address shortname name email phone opac_visible fiscal_calendar/);

#-------------------------------------------------------------------------------
package actor::org_unit::hours_of_operation;
use base qw/actor/;

__PACKAGE__->table( 'actor_hours_of_operation' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/dow_0_open dow_0_close dow_1_open dow_1_close dow_2_open dow_2_close
					dow_3_open dow_3_close dow_4_open dow_4_close dow_5_open dow_5_close
					dow_6_open dow_6_close/);

#-------------------------------------------------------------------------------
package actor::org_unit::closed_date;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit_closed' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/org_unit close_start close_end reason/);


#-------------------------------------------------------------------------------
package actor::org_unit_setting;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_unit_setting' );
__PACKAGE__->columns( Primary => qw/id/);
__PACKAGE__->columns( Essential => qw/org_unit name value/);


#-------------------------------------------------------------------------------
package actor::stat_cat;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owner name opac_visible usr_summary sip_field sip_format checkout_archive required allow_freetext/ );

#-------------------------------------------------------------------------------
package actor::stat_cat_entry;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat_entry' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/stat_cat owner value/ );

#-------------------------------------------------------------------------------
package actor::stat_cat_entry_default;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat_entry_default' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/stat_cat_entry stat_cat owner/ );

#-------------------------------------------------------------------------------
package actor::stat_cat_entry_user_map;
use base qw/actor/;

__PACKAGE__->table( 'actor_stat_cat_entry_usr_map' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/stat_cat stat_cat_entry target_usr/ );

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

__PACKAGE__->table( 'actor_usr_address' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/valid address_type usr street1 street2
				      city county state country post_code
				      within_city_limits/ );

#-------------------------------------------------------------------------------
package actor::org_address;
use base qw/actor/;

__PACKAGE__->table( 'actor_org_address' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/valid address_type org_unit street1 street2
				      city county state country post_code/ );

#-------------------------------------------------------------------------------
1;

