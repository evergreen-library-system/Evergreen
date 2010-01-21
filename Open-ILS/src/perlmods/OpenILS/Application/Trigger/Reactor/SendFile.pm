package   OpenILS::Application::Trigger::Reactor::SendFile;
use       OpenILS::Application::Trigger::Reactor;
use base 'OpenILS::Application::Trigger::Reactor';

# use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::RemoteAccount;

use strict;
use warnings;

sub ABOUT {
    return <<ABOUT;

The SendFile Reactor Module attempts to transfer a file to a remote server via
SCP, FTP or SFTP.

No default template is assumed, and all information is expected to be gathered
by the Event Definition through event parameters:
   ~ remote_host (required)
   ~ remote_user
   ~ remote_password
   ~ remote_account
   ~ remote_filename
   ~ ssh_privatekey
   ~ ssh_publickey
   ~ type (FTP, SFTP or SCP -- default FTP)
   ~ port
   ~ debug

The processed template is passed as "content" with the other params to
OpenILS::Utils::RemoteAccount.  See perldoc OpenILS::Utils::RemoteAccount for more.

TODO: allow config.remote_account.id to specify options.
ABOUT
}

sub handler {
    my $self = shift;
    my $env  = shift;
    my $params = $env->{params};

    $params->{content} = $self->run_TT($env) or return;
    my $connection = OpenILS::Utils::RemoteAccount->new(%$params) or return;
    return $connection->put;
}

1;

