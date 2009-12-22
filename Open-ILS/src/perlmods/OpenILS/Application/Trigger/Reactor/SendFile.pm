package   OpenILS::Application::Trigger::Reactor::SendFile;
use       OpenILS::Application::Trigger::Reactor;
use base 'OpenILS::Application::Trigger::Reactor';

# use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:logger/;

use Data::Dumper;
use Net::uFTP;
use Net::SSH2;      # because uFTP doesn't handle SSH keys (yet?)
use File::Temp;

$Data::Dumper::Indent = 0;

use strict;
use warnings;

our %keyfiles = ();

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
   ~ ssh_privatekey
   ~ ssh_publickey
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

SSH KEYS:

The use of ssh keys is preferred. 

The reactor attempts to use SSH keys where they are specified or otherwise found
in the runtime environment.  If only one key is specified, we attempt to derive
the corresponding filename based on the ssh-keygen defaults.  If either key is
specified, but both are not found (and readable) then the result is failure.  If
no key is specified, but keys are found, the key-based connections will be attempted,
but failure will be non-fatal.

ABOUT
}

sub plausible_dirs {
    # returns plausible locations of a .ssh subdir where SSH keys might be stashed
    # NOTE: these would need to be properly genericized w/ Makefule vars
    # in order to support Debian packaging and multiple EG's on one box.
    # Until that happens, we just rely on $HOME

    my @bases = (
       # '/openils/conf',     # __EG_CONFIG_DIR__
    );
    ($ENV{HOME}) and unshift @bases, $ENV{HOME};

    return grep {-d $_} map {"$_/.ssh"} @bases;
}

sub get_keyfiles {
    # populates %keyfiles hash
    # %keyfiles maps SSH_PRIVATEKEY => SSH_PUBLICKEY
    my $force = (@_ ? shift : 0);
    return %keyfiles if (%keyfiles and not $force);   # caching
    $logger->info("Checking for SSH keyfiles" . ($force ? ' (ignoring cache)' : ''));
    %keyfiles = ();  # reset to empty
    my @dirs = plausible_dirs();
    $logger->debug(scalar(@dirs) . " plausible dirs: " . join(', ', @dirs));
    foreach my $dir (@dirs) {
        foreach my $key (qw/rsa dsa/) {
            my $private = "$dir/id_$key";
            my $public  = "$dir/id_$key.pub";
            unless (-r $private) {
                $logger->debug("Key '$private' cannot be read: $!");
                next;
            }
            unless (-r $public) {
                $logger->debug("Key '$public' cannot be read: $!");
                next;
            }
            $keyfiles{$private} = $public;
        }
    }
    return %keyfiles;
}

sub param_keys {
    my $params = shift;
    my %keys = ();
    if ($params->{ssh_publickey } and not $params->{ssh_privatekey}) {
        $params->{ssh_privatekey} = $params->{ssh_publickey};        # try to guess missing private key name
        unless ($params->{ssh_privatekey} =~ s/\.pub$// and -r $params->{ssh_privatekey}) {
            $logger->error("No ssh_privatekey specified or found to pair with " . $params->{ssh_publickey});
            return;
        }
    }
    if ($params->{ssh_privatekey} and not $params->{ssh_publickey }) {
        $params->{ssh_publickey}  = $params->{ssh_privatekey} . '.pub'; # guess missing public key name
        unless (-r $params->{ssh_publickey}) {
            $logger->error("No ssh_publickey specified or found to pair with " . $params->{ssh_privatekey});
            return;
        }
    }

    # so now, we have either both ssh_p*key params or neither
    foreach (qw/ssh_publickey ssh_privatekey/) {
        unless (-r $params->{$_}) {
            $logger->error("$_ '" . $params->{$_} . "' cannot be read: $!");
            return;                 # quit w/ error if we fail on any user-specified key
        }
        $keys{$params->{ssh_privatekey}} = $params->{ssh_publickey};
    }
    return %keys;
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

    my $text = $self->run_TT($env) or return;
    my $tmp  = File::Temp->new();    # magical self-destructing tempfile
    print $tmp $text;
    $logger->info("SendFile Reactor: using tempfile $tmp");

    my %keys     = ();
    my $specific = 0;
    my @put_args = ($tmp->filename);      # same for scp_put and uFTP put
    push @put_args, $params->{remote_file} if $params->{remote_file};     # user can specify remote_file name, optionally

    unless ($params->{type} and $params->{type} eq 'FTP') {
        if ($params->{ssh_publickey} || $params->{ssh_privatekey}) {
            $specific = 1;
            %keys = param_keys($params) or return;  # we got one or both params, but they didn't pan out
        } else {
            %keys = get_keyfiles();     # optional "force" arg could be used here to empty cache
        }
    }

    if (%keys) {
        my $ssh2 = Net::SSH2->new();
        unless($ssh2->connect($host)) {
            $logger->warn("SSH2 connect FAILED: $!" . join(" ", $ssh2->error));
            $specific and return;
            %keys = ();     # forget the keys, we cannot connect
        }
        foreach (keys %keys) {
            my %auth_args = (
                privatekey => $_,
                publickey  => $keys{$_},
                rank => [qw/ publickey hostbased password /],
            );
            $params->{remote_user    } and $auth_args{username} = $params->{remote_user    };
            $params->{remote_password} and $auth_args{password} = $params->{remote_password};
            $params->{remote_host    } and $auth_args{hostname} = $params->{remote_host    };

            if ($ssh2->auth(%auth_args)) {
                if ($ssh2->scp_put(@put_args)) {
                    $logger->info("SendFile Reactor: successfully sent ${host} " . join(' --> ', @put_args));
                    return 1;
                } else {
                    $logger->error("SendFile Reactor: put to $host failed with error: $!");
                    return;
                }
            } elsif ($specific) {
                $logger->error("Abort reactor: ssh2->auth FAILED for $host using $_: $!");
                return;
            } else {
                $logger->notice("Unsuccessful keypair: ssh2->auth FAILED for $host using $_: $!");
            }
        }
    }
    # my $conf = OpenSRF::Utils::SettingsClient->new;
    # $$env{something_hardcoded} = $conf->config_value('category', 'whatever');

    # Try w/ non-key uFTP methods
    my %options = ();
    foreach (qw/debug type port/) {
        $options{$_} = $params->{$_} if $params->{$_};
    }
    my $ftp = Net::uFTP->new($host, %options);

    my @login_args = ();
    foreach (qw/remote_user remote_password remote_account/) {
        push @login_args, $params->{$_} if $params->{$_};
    }
    unless ($ftp->login(@login_args)) {
        $logger->error("SendFile Reactor: failed login to $host w/ args(" . join(',', @login_args) . ")");
        return;
    }

    my $filename = $ftp->put(@put_args);
    if ($filename) {
        $logger->info("SendFile Reactor: successfully sent ${host} $tmp --> $filename");
        return 1;
    } else {
        $logger->error("SendFile Reactor: put to $host failed with error: $!");
        return;
    }
}

1;

