package   OpenILS::Utils::RemoteAccount;

# use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:logger/;

use Data::Dumper;
use Net::uFTP;
use Net::SSH2;      # because uFTP doesn't handle SSH keys (yet?)
use File::Temp;

$Data::Dumper::Indent = 0;

use strict;
use warnings;

use Carp;

our $AUTOLOAD;

our %keyfiles = ();

my %fields = (
    remote_host     => undef,
    remote_user     => undef,
    remote_password => undef,
    remote_account  => undef,
    remote_file     => undef,
    ssh_privatekey  => undef,
    ssh_publickey   => undef,
    type            => undef,
    port            => undef,
    content         => undef,
    localfile       => undef,
    tempfile        => undef,
    error           => undef,
    specific        => 0,
    debug           => 0,
);


=pod 

The Remote Account module attempts to transfer a file to/from a remote server.
Net::uFTP is used, encapsulating the available options of SCP, FTP and SFTP.

All information is expected to be gathered by the Event Definition through event parameters:
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

We attempt to use SSH keys where they are specified or otherwise found
in the runtime environment.  If only one key is specified, we attempt to derive
the corresponding filename based on the ssh-keygen defaults.  If either key is
specified, but both are not found (and readable) then the result is failure.  If
no key is specified, but keys are found, the key-based connections will be attempted,
but failure will be non-fatal.

=cut

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
    my $self  = shift;
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
    my $self = shift;
    my %keys = ();
    if ($self->ssh_publickey and not $self->ssh_privatekey) {
        my $private = $self->ssh_publickey;
        unless ($private and $private =~ s/\.pub$// and -r $self->ssh_privatekey) {        # try to guess missing private key name
            $logger->error("No ssh_privatekey specified or found to pair with " . $self->ssh_publickey);
            return;
        }
        $self->ssh_privatekey($private);
    }
    if ($self->ssh_privatekey and not $self->ssh_publickey) {
        my $pub = $self->ssh_privatekey . '.pub'; # guess missing public key name
        unless (-r $pub) {
            $logger->error("No ssh_publickey specified or found to pair with " . $self->ssh_privatekey);
            return;
        }
        $self->ssh_publickey($pub);
    }

    # so now, we have either both ssh_p*keys params or neither
    foreach (qw/ssh_publickey ssh_privatekey/) {
        unless (-r $self->{$_}) {
            $logger->error("$_ '" . $self->{$_} . "' cannot be read: $!");
            return;                 # quit w/ error if we fail on any user-specified key
        }
    }
    $keys{$self->ssh_privatekey} = $self->ssh_publickey;
    return %keys;
}

sub new_tempfile {
    my $self = shift;
    my $text = shift || $self->content || ''; 
    my $tmp  = File::Temp->new();      # magical self-destructing tempfile
    # print $tmp "THIS IS TEXT\n";
    print $tmp $text  or  $logger->error(__PACKAGE__ . " : could not write to tempfile '$tmp'");
    close $tmp;
    $self->tempfile($tmp);             # save the object
    $self->localfile($tmp->filename);  # save the filename
    $logger->info(__PACKAGE__ . " : using tempfile $tmp");
    return $self->localfile;           # return the filename
}

sub get {
    my $self   = shift;
    my $params = shift;

    $self->init($params);   # secondary init
}

sub outbound_file {
    my $self   = shift;
    my $params = shift;

    unless (defined $self->content or $self->localfile) {   # content can be emptystring
        $logger->error($self->error("No content or localfile specified -- nothing to send"));
        return;
    }

    # tricky subtlety: we want to use the most recently specified options 
    #   with priority order: filename, content, old filename, old content.
    # 
    # The $params->{x} will already match $self->x after the init above, 
    # so the checks using $params below are for whether the value was specified NOW (via put()) or not.
    # 
    # if we got a new localfile value, we use it
    # else if the content is new to this call, build a new tempfile w/ it,
    # else use existing localfile,
    # else build new tempfile w/ content already specified via new()

    return $params->{localfile} || (
        (defined $params->{content})          ?
         $self->new_tempfile($self->content)  :     # $self->content is same value as $params->{content}
        ($self->localfile || $self->new_tempfile($self->content))
    );
}

sub put {
    my $self   = shift;
    my $params = shift;

    $self->init($params);   # secondary init
   
    my $localfile = $self->outbound_file($params) or return;

    my %keys = ();
    $self->{put_args} = [$localfile];      # same for scp_put and uFTP put

    push @{$self->{put_args}}, $self->remote_file if $self->remote_file;     # user can specify remote_file name, optionally

    unless ($self->type and $self->type eq 'FTP') {
        if ($self->ssh_publickey || $self->ssh_privatekey) {
            $self->specific(1);
            %keys = $self->param_keys() or return;  # we got one or both params, but they didn't pan out
        } else {
            %keys = get_keyfiles();     # optional "force" arg could be used here to empty cache
        }
    }

    my $try;
    $try = $self->put_ssh2(%keys) if (%keys);
    return $try if $try;  # if we had keys and they worked, we're done

    # Otherwise, try w/ non-key uFTP methods
    return $self->put_uftp;
}

sub put_ssh2 {
    my $self = shift;
    my %keys = (@_);

    $logger->info("*** attempting put with ssh keys");
    my $ssh2 = Net::SSH2->new();
    unless($ssh2->connect($self->remote_host)) {
        $logger->warn($self->error("SSH2 connect FAILED: $!" . join(" ", $ssh2->error)));
        $self->specific and return;     # user told us what key(s) she wanted, and it failed.
        %keys = ();     # forget the keys, we cannot connect
    }
    foreach (keys %keys) {
        my %auth_args = (
            privatekey => $_,
            publickey  => $keys{$_},
            rank => [qw/ publickey hostbased password /],
        );
        $self->remote_user     and $auth_args{username} = $self->remote_user    ;
        $self->remote_password and $auth_args{password} = $self->remote_password;
        $self->remote_host     and $auth_args{hostname} = $self->remote_host    ;

        if ($ssh2->auth(%auth_args)) {
            if ($ssh2->scp_put( @{$self->{put_args}} )) {
                $logger->info(sprintf __PACKAGE__ . " : successfully sent %s %s", $self->remote_host, join(' --> ', @{$self->{put_args}} ));
                return 1;
            } else {
                $logger->error($self->error(sprintf __PACKAGE__ . " : put to %s failed with error: $!", $self->remote_host));
                return;
            }
        } elsif ($self->specific) {
            $logger->error($self->error(sprintf "Abort: ssh2->auth FAILED for %s using %s: $!", $self->remote_host, $_));
            return;
        } else {
            $logger->notice($self->error(sprintf "Unsuccessful keypair: ssh2->auth FAILED for %s using %s: $!", $self->remote_host, $_));
        }
    }
}

sub uftp {
    my $self = shift;
    my %options = ();
    foreach (qw/debug type port/) {
        $options{$_} = $self->{$_} if $self->{$_};
    }
    # TODO: eval wrapper, set $self->error($!) on failure
    my $ftp = Net::uFTP->new($self->remote_host, %options) or return;

    my @login_args = ();
    foreach (qw/remote_user remote_password remote_account/) {
        push @login_args, $self->{$_} if $self->{$_};
    }
    unless ($ftp->login(@login_args)) {
        $logger->error(__PACKAGE__ . ' : ' . $self->error("failed login to " . $self->remote_host . " w/ args(" . join(',', @login_args) . ')'));
        return;
    }
    return $ftp;
}

sub put_uftp {
    my $self = shift;
    my $ftp = $self->uftp or return;
    my $filename = $ftp->put(@{$self->{put_args}});
    if ($filename) {
        $logger->info(__PACKAGE__ . " : successfully sent $self->remote_host $self->localfile --> $filename");
        return $filename;
    } else {
        $logger->error(__PACKAGE__ . ' : ' . $self->error("put to " . $self->remote_host . " failed with error: $!"));
        return;
    }
}

sub init {
    my $self   = shift;
    my $params = shift;
    my @required = @_;  # qw(remote_host) ;     # nothing required now

    foreach (keys %{$self->{_permitted}}) {
        $self->{$_} = $params->{$_} if defined $params->{$_};
    }

    foreach (@required) {
        unless ($self->{$_}) {
            $logger->error("Required parameter $_ not specified");
            return;
        }
    }
    return $self;
}


sub new {
    my( $class, %args ) = @_;
    my $self = { _permitted => \%fields, %fields };

	bless $self, $class;

    $self->init(\%args); # or croak "Initialization error caused by bad args";
    return $self;
}

sub DESTROY { 
	# in order to create, we must first ...
}

sub AUTOLOAD {
	my $self  = shift;
	my $class = ref($self) or croak "$self is not an object";
	my $name  = $AUTOLOAD;

	$name =~ s/.*://;   #   strip leading package stuff

	unless (exists $self->{_permitted}->{$name}) {
		croak "Cannot access '$name' field of class '$class'";
	}

	if (@_) {
		return $self->{$name} = shift;
	} else {
		return $self->{$name};
	}
}

1;
