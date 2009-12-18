package   OpenILS::Application::Trigger::Reactor::SendFile;
use       OpenILS::Application::Trigger::Reactor;
use base 'OpenILS::Application::Trigger::Reactor';

# use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:logger/;

use Data::Dumper;
use Net::uFTP;
use File::Temp;

$Data::Dumper::Indent = 0;

use strict;
use warnings;

sub ABOUT {
    return <<ABOUT;

The SendFile Reactor Module attempts to transfer a file to a remote server.
Net::uFTP is used, encapsulating the available options of SCP, FTP and SFTP.

No default template is assumed, and all information is expected to be gathered
by the Event Definition through event parameters:
   ~ remote_host (required)
   ~ remote_user
   ~ remote_password
   ~ remote_account
   ~ type (FTP, SFTP or SCP -- default FTP)
   ~ port
   ~ debug

The latter three are optionally passed to the Net::uFTP constructor.

Note: none of the parameters are actually required, except remote_host.
That is because remote_user, remote_password and remote_account can all be 
extrapolated from other sources, as the Net::FTP docs describe:

    If no arguments are given then Net::FTP uses the Net::Netrc package
        to lookup the login information for the connected host.

    If no information is found then a login of anonymous is used.

    If no password is given and the login is anonymous then anonymous@
        will be used for password.

Note that specifying a password will require you to specify a user.
Similarly, specifying an account requires both user and password.
That is, there are no assumed defaults when the latter arguments are used.

ABOUT
}

sub handler {
    my $self = shift;
    my $env  = shift;
    my $params = $env->{params};

    my $host = $params->{remote_host};
    unless ($host) {
        $logger->error("No remote_host specified in env");
        return;
    }

    my %options = ();
    foreach (qw/debug type port/) {
        $options{$_} = $params->{$_} if $params->{$_};
    }
    my $ftp = Net::uFTP->new($host, %options);

    # my $conf = OpenSRF::Utils::SettingsClient->new;
    # $$env{something_hardcoded} = $conf->config_value('category', 'whatever');

    my $text = $self->run_TT($env) or return;
    my $tmp  = File::Temp->new();    # magical self-destructing tempfile
    print $tmp $text;
    $logger->info("SendFile Reactor: using tempfile $tmp");

    my @login_args = ();
    foreach (qw/remote_user remote_password remote_account/) {
        push @login_args, $params->{$_} if $params->{$_};
    }
    unless ($ftp->login(@login_args)) {
        $logger->error("SendFile Reactor: failed login to $host w/ args(" . join(',', @login_args) . ")");
        return;
    }

    my @put_args = ($tmp);
    push @put_args, $params->{remote_file} if $params->{remote_file};     # user can specify remote_file name, optionally
    my $filename = $ftp->put(@put_args);
    if ($filename) {
        $logger->info("SendFile Reactor: successfully sent ${host} $filename");
        return 1;
    }

    $logger->error("SendFile Reactor: put to $host failed with error: $!");
    return;
}

1;

