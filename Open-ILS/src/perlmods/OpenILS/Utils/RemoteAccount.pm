package   OpenILS::Utils::RemoteAccount;

# use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:logger/;

use Data::Dumper;
use Net::uFTP;
use Net::SSH2;      # because uFTP doesn't handle SSH keys (yet?)
use File::Temp;
use File::Basename;
# use Error;

$Data::Dumper::Indent = 0;

use strict;
use warnings;

use Carp;

our $AUTOLOAD;

our %keyfiles = ();

my %fields = (
    accound_object  => undef,
    remote_host     => undef,
    remote_user     => undef,
    remote_password => undef,
    remote_account  => undef,
    remote_file     => undef,
    remote_path     => undef,   # not really doing anything with this... yet.
    ssh_privatekey  => undef,
    ssh_publickey   => undef,
    type            => undef,
    port            => undef,
    content         => undef,
    local_file      => undef,
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

sub local_keyfiles {
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
    print $tmp $text  or  $logger->error($self->_error("could not write to tempfile '$tmp'"));
    close $tmp;
    $self->tempfile($tmp);             # save the object
    $self->local_file($tmp->filename);  # save the filename
    $logger->info(_pkg("using tempfile $tmp"));
    return $self->local_file;           # return the filename
}

sub outbound_file {
    my $self   = shift;
    my $params = shift;

    unless (defined $self->content or $self->local_file) {   # content can be emptystring
        $logger->error($self->_error("No content or local_file specified -- nothing to send"));
        return;
    }

    # tricky subtlety: we want to use the most recently specified options 
    #   with priority order: filename, content, old filename, old content.
    # 
    # The $params->{x} will already match $self->x after the secondary init,
    # so the checks using $params below are for whether the value was specified NOW (e.g. via put()) or not.
    # 
    # if we got a new local_file value, we use it
    # else if the content is new to this call, build a new tempfile w/ it,
    # else use existing local_file,
    # else build new tempfile w/ content already specified via new()

    return $params->{local_file} || (
        (defined $params->{content})          ?
         $self->new_tempfile($self->content)  :     # $self->content is same value as $params->{content}
        ($self->local_file || $self->new_tempfile($self->content))
    );
}

sub key_check {
    my $self   = shift;
    my $params = shift;

    return if ($params->{type} and $params->{type} eq 'FTP');   # Forget it, user specified regular FTP
    return if (   $self->type  and    $self->type  eq 'FTP');   # Forget it, user specified regular FTP

    if ($self->ssh_publickey || $self->ssh_privatekey) {
        $self->specific(1);
        return $self->param_keys();  # we got one or both params, but they didn't pan out
    }
    return local_keyfiles();     # optional "force" arg could be used here to empty cache
}


# TOP LEVEL methods
# TODO: delete for both uFTP and SSH2
# TODO: handle IO::Scalar and IO::File for uFTP

sub get {
    my $self   = shift;
    my $params = shift;
    if (! ref $params) {
        $params = {remote_file => $params} ;
    }

    $self->init($params);   # secondary init

    $self->{get_args} = [$self->remote_file];      # same for scp_put and uFTP put
    push @{$self->{get_args}}, $self->local_file if defined $self->local_file;
    
    # $self->content($content);

    my %keys = $self->key_check($params);
    if (%keys) {
        my $try = $self->get_ssh2(\%keys, @{$self->{get_args}});
        return $try if $try;  # if we had keys and they worked, we're done
    }

    # Otherwise, try w/ non-key uFTP methods
    return $self->get_uftp(@{$self->{get_args}});
}

sub put {
    my $self   = shift;
    my $params = shift;
    if (! ref $params) {
        $params = {local_file => $params} ;
    }

    $self->init($params);   # secondary init
   
    my $local_file = $self->outbound_file($params) or return;

    $self->{put_args} = [$local_file];      # same for scp_put and uFTP put
    if (defined $self->remote_path and not defined $self->remote_file) {
        $self->remote_file($self->remote_path . '/' . basename($local_file));   # if we know just the dir
    }
    if (defined $self->remote_file) {
        push @{$self->{put_args}}, $self->remote_file;     # user can specify remote_file name, optionally
    }

    my %keys = $self->key_check($params);
    if (%keys) {
        $self->put_ssh2(\%keys, @{$self->{put_args}}) and return $self->remote_file;
        # if we had keys and they worked, we're done
    }

    # Otherwise, try w/ non-key uFTP methods
    return $self->put_uftp(@{$self->{put_args}});
}

sub ls {
    my $self   = shift;
    my $params = shift;
    my @targets = @_;
    if (! ref $params) {
        unshift @targets, ($params || '.');   # If it was just a string, it's the first target, else default pwd
        delete $self->{remote_file}; # overriding any target in the object previously.
        $params = {};                # make params a normal hashref again
    } else {
        if ($params->{remote_file} and @_) {
            $logger->warn($self->_error("Ignoring ls parameter remote_file for subsequent args"));
            delete $params->{remote_file};
        }
        $self->init($params);   # secondary init
        $self->remote_file and (! @targets) and push @targets, $self->remote_file;  # if remote_file is there, and there's nothing else, use it
        delete $self->{remote_file};
    }

    $self->{ls_args} = \@targets;

    my %keys = $self->key_check($params);
    if (%keys) {
        # $logger->info("*** calling ls_ssh2(keys, '" . join("', '", (scalar(@targets) ? map {defined $_ ? $_ : '' } @targets : ())) . "') with ssh keys");
        my @try = $self->ls_ssh2(\%keys, @targets);
        return @try if @try;  # if we had keys and they worked, we're done
    }

    # Otherwise, try w/ non-key uFTP methods
    return $self->ls_uftp(@targets);
}

# Internal Mechanics

sub _ssh2 {
    my $self = shift;
    $self->{ssh2} and return $self->{ssh2};     # caching
    my $keys = shift;

    my $ssh2 = Net::SSH2->new();
    unless($ssh2->connect($self->remote_host)) {
        $logger->warn($self->error("SSH2 connect FAILED: $!" . join(" ", $ssh2->error)));
        return;     # we cannot connect
    }

    my $success  = 0;
    my @privates = keys %$keys;
    my $count    = scalar @privates;
    foreach (@privates) {
        if ($self->auth_ssh2($ssh2, $self->auth_ssh2_args($_, $keys->{$_}))) {
            $success++;
            last;
        }
    }
    unless ($success) {
        $logger->error($self->error("All ($count) keypair(s) FAILED for " . $self->remote_host));
        return;
    }
    return $self->{ssh2} = $ssh2;
}

sub auth_ssh2 {
    my $self = shift;
    my $ssh2 = shift;
    my %auth_args = @_;
    $ssh2 or return;

    my $host = $auth_args{hostname}   || 'UNKNOWN';
    my $key  = $auth_args{privatekey} || 'UNKNOWN';
    my $msg  = "ssh2->auth by keypair for $host using $key"; 
    if ($ssh2->auth(%auth_args)) {
        $logger->info("Successful $msg");
         return 1;
    }

    if ($self->specific) {
        $logger->error($self->error("Aborting. FAILED $msg: " . ($ssh2->error || '')));
    } else {
        $logger->warn($self->error("Unsuccessful keypair: FAILED $msg: " . ($ssh2->error || '')));
    }
    return;
}

sub auth_ssh2_args {
    my $self = shift;
    my %auth_args = (
        privatekey => shift,
        publickey  => shift,
        rank => [qw/ publickey hostbased password /],
    );
    $self->remote_user     and $auth_args{username} = $self->remote_user    ;
    $self->remote_password and $auth_args{password} = $self->remote_password;
    $self->remote_host     and $auth_args{hostname} = $self->remote_host    ;
    return %auth_args;
}

sub put_ssh2 {
    my $self = shift;
    my $keys = shift;    # could have many keypairs here
    unless (@_) {
        $logger->error($self->_error("put_ssh2 called without target: nothing to put!"));
        return;
    }
    
    $logger->info("*** attempting put (" . join(", ", @_) . ") with ssh keys");
    my $ssh2 = $self->_ssh2($keys) or return;
    my $res;
    if ($res = $ssh2->scp_put( @_ )) {
        $logger->info(_pkg("successfully sent", $self->remote_host, join(' --> ', @_ )));
        return $res;
    }
    $logger->error($self->_error(sprintf "put with keys to %s failed with error: $!", $self->remote_host));
    return;
}

sub get_ssh2 {
    my $self = shift;
    my $keys = shift;    # could have many keypairs here
    unless (@_) {
        $logger->error($self->_error("get_ssh2 called without target: nothing to get!"));
        return;
    }
    
    $logger->info("*** get args: " . Dumper(\@_));
    $logger->info("*** attempting get (" . join(", ", map {$_ =~ /\S/ ? $_ : '*Object'} map {$_ || '*Object'} @_) . ") with ssh keys");
    my $ssh2 = $self->_ssh2($keys) or return;
    my $res;
    if ($res = $ssh2->scp_get( @_ )) {
        $logger->info(_pkg("successfully got", $self->remote_host, join(' --> ', @_ )));
        return $res;
    }
    $logger->error($self->_error(sprintf "get with keys from %s failed with error: $!", $self->remote_host));
    return;
}

sub ls_ssh2 {
    my $self = shift;
    my @list = $self->ls_ssh2_full(@_);
    @list and return sort map {$_->{slash_path}} @list;
#   @list and return sort grep {$_->{name} !~ /./ and {$_->{name} !~ /./ } map {$_->{slash_path}} @list;
}

sub ls_ssh2_full {
    my $self = shift;
    my $keys = shift;    # could have many keypairs here
    my @targets = grep {defined} @_;

    $logger->info("*** attempting ls ('" . join("', '", @targets) . "') with ssh keys");
    my $ssh2 = $self->_ssh2($keys) or return;
    my $sftp = $ssh2->sftp         or return;

    my @list = ();
    foreach my $target (@targets) {
        my ($dir, $file);
        $dir = $sftp->opendir($target);
        unless ($dir) {
            $file = $sftp->stat($target);
            if ($file) {
                $file->{slash_path} = $self->_slash_path($target, $file->{name});     # it was a file, not a dir.  That's OK.
                push @list, $file;
            } else {
                $logger->warn($self->_error("sftp->opendir($target) failed: " . $sftp->error));
            }
            next;
        }
        while ($file = $dir->read()) {
            $file->{slash_path} = $self->_slash_path($target, $file->{name});
            push @list, $file;
            # foreach (sort keys %$line) { printf "   %20s => %s\n", $_, $line->{$_}; }
        }
    }
    return @list;

}

sub _slash_path {    # not OO
    my $self = shift;
    my $dir  = shift || '.';
    my $file = shift || '';
    return $dir . ($dir =~ /\/$/ ? '' : '/') . $file;
}

sub _uftp {
    my $self = shift;
    my %options = ();
    $self->{uftp} and return $self->{uftp};     # caching
    foreach (qw/debug type port/) {
        $options{$_} = $self->{$_} if $self->{$_};
    }
    
    my $ftp = Net::uFTP->new($self->remote_host, %options);
    unless ($ftp) {
        $logger->error($self->_error('Net::uFTP->new("' . $self->remote_host . ", ...) FAILED: $@"));
        return;
    }

    my @login_args = ();
    foreach (qw/remote_user remote_password remote_account/) {
        $self->{$_} or last;
        push @login_args, $self->{$_};
    }
    eval { $ftp->login(@login_args) };
    if ($@) {
        $logger->error($self->_error("failed login to", $self->remote_host,  "w/ args(" . join(',', @login_args) . ") : $@"));
        return;
    }
    return $self->{uftp} = $ftp;
}

sub put_uftp {
    my $self = shift;
    my $ftp = $self->_uftp or return;
    my $filename;
    eval { $filename = $ftp->put(@{$self->{put_args}}) };
    if ($@ or ! $filename) {
        $logger->error($self->_error("put to", $self->remote_host, "failed with error: $@"));
        return;
    }
    $self->remote_file($filename);
    $logger->info(_pkg("successfully sent", $self->remote_host, $self->local_file, '-->', $filename));
    return $filename;
}

sub get_uftp {
    my $self = shift;
    my $ftp = $self->_uftp or return;
    my $filename;
    eval { $filename = $ftp->get(@{$self->{get_args}}) };
    if ($@ or ! $filename) {
        $logger->error($self->_error("get from", $self->remote_host, "failed with error: $@"));
        return;
    }
    $self->local_file($filename);
    $logger->info(_pkg("successfully retrieved $filename <--", $self->remote_host . '/' . $self->remote_file));
    return $self->local_file;
}

sub ls_uftp {
    my $self = shift;
    my $ftp = $self->_uftp or return;
    my @list;
    foreach (@_) {
        my @part;
        eval { @part = $ftp->ls($_) };
        if ($@) {
            $logger->error($self->_error("ls from",  $self->remote_host, "failed with error: $@"));
            next;
        }
        push @list, @part;
    }
    return @list;
}

sub delete_uftp {
    my $self = shift;
    my $ftp = $self->_uftp or return;
    return $ftp->delete(shift);
}

sub _pkg {      # Not OO
    return __PACKAGE__ . ' : ' unless @_;
    return __PACKAGE__ . ' : ' . join(' ', @_);
}

sub _error {
    my $self = shift;
    return _pkg($self->error(join(' ',@_)));
}

sub init {
    my $self   = shift;
    my $params = shift;
    my @required = @_;  # qw(remote_host) ;     # nothing required now

    if ($params->{account_object}) {    # if we got passed an object, we initialize off that first
        $self->{remote_host    } = $params->{account_object}->host;
        $self->{remote_user    } = $params->{account_object}->username;
        $self->{remote_password} = $params->{account_object}->password;
        $self->{remote_account } = $params->{account_object}->account;
        $self->{remote_path    } = $params->{account_object}->path;     # not really the same as remote_file, maybe expand on this later
    }

    foreach (keys %{$self->{_permitted}}) {
        $self->{$_} = $params->{$_} if defined $params->{$_};   # possibly override settings from object
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
    my ($class, %args) = @_;
    my $self = { _permitted => \%fields, %fields };

	bless $self, $class;

    $self->init(\%args); # or croak "Initialization error caused by bad args";
    return $self;
}

sub DESTROY { 
	# in order to create, we must first ...
	my $self  = shift;
    $self->{ssh2} and $self->{ssh2}->disconnect();  # let the other end know we're done.
    $self->{uftp} and $self->{uftp}->quit();  # let the other end know we're done.
}

sub AUTOLOAD {
	my $self  = shift;
	my $class = ref($self) or croak "AUTOLOAD error: $self is not an object";
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

