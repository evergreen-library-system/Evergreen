package OpenILS::Application::Storage::CDBI::permission;
our $VERSION = 1;

#-------------------------------------------------------------------------------
package permission;
use base qw/OpenILS::Application::Storage::CDBI/;
#-------------------------------------------------------------------------------
package permission::perm_list;
use base qw/permission/;
__PACKAGE__->table('permission_perm_list');
__PACKAGE__->columns(Primary => qw/id/);
__PACKAGE__->columns(Essential => qw/code description/);
#-------------------------------------------------------------------------------
package permission::grp_tree;
use base qw/permission/;
__PACKAGE__->table('permission_grp_tree');
__PACKAGE__->columns(Primary => qw/id/);
__PACKAGE__->columns(Essential => qw/name parent description perm_interval
                     temporary_perm_interval application_perm usergroup
                     hold_priority erenew/);
#-------------------------------------------------------------------------------
package permission::usr_grp_map;
use base qw/permission/;
__PACKAGE__->table('permission_usr_grp_map');
__PACKAGE__->columns(Primary => qw/id/);
__PACKAGE__->columns(Essential => qw/usr grp/);
#-------------------------------------------------------------------------------
package permission::usr_perm_map;
use base qw/permission/;
__PACKAGE__->table('permission_usr_perm_map');
__PACKAGE__->columns(Primary => qw/id/);
__PACKAGE__->columns(Essential => qw/usr perm depth grantable/);
#-------------------------------------------------------------------------------
package permission::grp_perm_map;
use base qw/permission/;
__PACKAGE__->table('permission_grp_perm_map');
__PACKAGE__->columns(Primary => qw/id/);
__PACKAGE__->columns(Essential => qw/grp perm depth grantable/);
#-------------------------------------------------------------------------------
package permission::usr_work_ou_map;
use base qw/permission/;
__PACKAGE__->table('permission_usr_work_ou_map');
__PACKAGE__->columns(Primary => qw/id/);
__PACKAGE__->columns(Essential => qw/usr work_ou/);
#-------------------------------------------------------------------------------
1;

