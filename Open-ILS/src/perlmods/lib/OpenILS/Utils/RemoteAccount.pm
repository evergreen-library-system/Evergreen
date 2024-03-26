package OpenILS::Utils::RemoteAccount;

# use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:logger/;

use Data::Dumper;
use IO::Pty;
use Net::FTP;
use Net::SSH2;
use Net::SFTP::Foreign;
use File::Temp;
use File::Basename;
use File::Spec;
use Text::Glob qw( match_glob glob_to_regex );
# use Error;

$Data::Dumper::Indent = 0;

use strict;
use warnings;

use Carp;

our $AUTOLOAD;

our %keyfiles = ();

my %fields = (
    account_object  => undef,
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
    single_ext      => undef,
    specific        => 0,
    debug           => 0,
);


=head1 NAME 

OpenILS::Utils::RemoteAccount - Encapsulate FTP, SFTP and SSH file transactions for Evergreen

=head1 DESCRIPTION

The Remote Account module attempts to transfer a file to/from a remote server.
Net::FTP, Net::SSH2 or Net::SFTP::Foreign is used.

=head1 PARAMETERS

All information is expected to be supplied by the caller via parameters:
   ~ remote_host (required)
   ~ remote_user
   ~ remote_password
   ~ remote_account
   ~ ssh_privatekey
   ~ ssh_publickey
   ~ type (FTP, SFTP or SCP -- default FTP)
   ~ port
   ~ debug

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

=head2 SSH KEYS:

The use of ssh keys is preferred.  Explicit specification of connection type will prevent
multiple attempts to the same server.  Therefore, using the type parameter is also recommended.

If the type is not explicit, we attempt to use SSH keys where they are specified or otherwise found
in the runtime environment.  If only one key is specified, we attempt to derive
the corresponding filename based on the ssh-keygen defaults.  If either key is
specified, but both are not found (and readable) then the result is failure.  If
no key or type is specified, but keys are found, the key-based connections will be attempted,
but failure will be non-fatal.

=cut

sub plausible_dirs {
    # returns plausible locations of a .ssh subdir where SSH keys might be stashed
    # NOTE: these would need to be properly genericized w/ Makefile vars
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

sub get {
    my $self   = shift;
    my $params = shift;
    if (! ref $params) {
        $params = {remote_file => $params} ;
    }

    $self->init($params);   # secondary init

    $self->{get_args} = [$self->remote_file];      # same for scp_put and FTP put
    push @{$self->{get_args}}, $self->local_file if defined $self->local_file;
    
    # $self->content($content);

    if ($self->type eq "FTP") {
        return $self->get_ftp(@{$self->{get_args}});
    } elsif ($self->type eq "SFTP") {
        return $self->get_sftp(@{$self->{get_args}});
    } else {
        my %keys = $self->key_check($params);
        return $self->get_ssh2(\%keys, @{$self->{get_args}});
    }
}

sub put {
    my $self   = shift;
    my $params = shift;
    if (! ref $params) {
        $params = {local_file => $params} ;
    }

    $self->init($params);   # secondary init
   
    my $local_file = $self->outbound_file($params) or return;

    $self->{put_args} = [$local_file];      # same for scp_put and FTP put
    if (defined $self->remote_path and not defined $self->remote_file) {
        my $rpath = $self->remote_path;
        my $fname = basename($local_file);
        if ($rpath =~ /^(.*)\*+(.*)$/) {    # if the path has an asterisk in it, like './incoming/*.tst'
            my $head = $1;
            my $tail = $2;
            if ($tail =~ /\//) {
                $logger->warn($self->_error("remote path '$rpath' has dir slashes AFTER an asterisk.  Cannot determine target dir"));
                return;
            }
            if ($self->single_ext) {
                $tail =~ /\./ and $fname =~ s/\./_/g;    # if dot in tail, replace dots in fname (w/ _)
            }
            $self->remote_file($head . $fname . $tail);
        } else {
            $self->remote_file($rpath . '/' . $fname);   # if we know just the dir
        }
    }

    if (defined $self->remote_file) {
        push @{$self->{put_args}}, $self->remote_file;   # user can specify remote_file name, optionally
    }

    if ($self->type eq "FTP") {
        return $self->put_ftp(@{$self->{put_args}});
    } elsif ($self->type eq "SFTP") {
        return $self->put_sftp(@{$self->{put_args}});
    } else {
        my %keys = $self->key_check($params);
        $self->put_ssh2(\%keys, @{$self->{put_args}}) and return $self->remote_file;
    }
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

    if ($self->type eq "FTP") {
        return $self->ls_ftp(@targets);
    } elsif ($self->type eq "SFTP") {
        return $self->ls_sftp(@targets);
    } else {
        my %keys = $self->key_check($params);
        # $logger->info("*** calling ls_ssh2(keys, '" . join("', '", (scalar(@targets) ? map {defined $_ ? $_ : '' } @targets : ())) . "') with ssh keys");
        return $self->ls_ssh2(\%keys, @targets);
    }
}

sub delete {
    my $self   = shift;
    my $params = shift;

    $params = {remote_file => $params} unless ref $params;
    $self->init($params); # secondary init

    my $file = $params->{remote_file};

    if (!$file) {
        $logger->warn("No file specified for deletion");
        return undef;
    }

    $logger->info("Deleting remote file '$file'");

    if ($self->type eq "FTP") {
        return $self->delete_ftp($file);
    } elsif ($self->type eq "SFTP") {
        return $self->delete_sftp($file);
    } else {
	my %keys = $self->key_check($params);
	return $self->delete_ssh2(\%keys, $file);
    }
}


# Checks if the filename part of a pathname has one or more glob characters
# We split out the filename portion of the path
# Detect glob or no glob.
# returns: directory, regex for matching filenames
sub glob_parse {
    my $self = shift;
    my $path = shift or return;
    my ($vol, $dir, $file) = File::Spec->splitpath($path); # we don't care about attempted globs in mid-filepath
    my $front = $vol ? File::Spec->catdir($vol, $dir) : $dir;
    $file =~ /\*/ and return ($front, glob_to_regex($file));
    $file =~ /\?/ and return ($front, glob_to_regex($file));
    $logger->debug("No glob detected in '$path'");
    return;
}


# Internal Mechanics

sub _sftp {
    my $self = shift;
    $self->{sftp} and return $self->{sftp};     # caching
    my $sftp = Net::SFTP::Foreign->new($self->remote_host, user => $self->remote_user, password => $self->remote_password,
                                       more => [-o => "StrictHostKeyChecking=no"]);
    $sftp->error and $logger->error("SFTP connect FAILED: " . $sftp->error);
    return $self->{sftp} = $sftp;
}

sub put_sftp {
    my $self = shift;
    my $filename = $self->_sftp->put(@{$self->{put_args}}); 
    if ($self->_sftp->error or not $filename) {
        $logger->error(
            $self->_error(
                "SFTP put to", $self->remote_host, "failed with error: $self->_sftp->error"
            )
        );
        return;
    }
    
    $self->remote_file($filename);
    $logger->info(
        _pkg(
            "successfully sent", $self->remote_host, $self->local_file, "-->",
            $filename
        )
    );
    return $filename;
}

sub get_sftp {
    my $self = shift;
    my $remote_filename = $self->{get_args}->[0];
    my $filename = $self->{get_args}->[1];
    my $success = $self->_sftp->get(@{$self->{get_args}});
    if ($self->_sftp->error or not $success) {
        $logger->error(
            $self->_error(
                "get from", $self->remote_host, "failed with error: $self->_sftp->error"
            )
        );
        return;
    }

    $self->local_file($filename);
    $logger->info(
        _pkg(
            "successfully retrieved $filename <--", $self->remote_host . '/' .
            $self->remote_file
        )
    );
    return $self->local_file;

}

#$sftp->ls($path) or die 'could not ls: ' . $sftp->error;
sub ls_sftp {   # returns full path like: dir/path/file.ext
    my $self = shift;
    my @list;

    foreach (@_) {
        my ($dirpath, $regex) = $self->glob_parse($_);
        my $dirtarget = $dirpath || $_;
        $dirtarget =~ s/\/+$//;
        my @part = @{$self->_sftp->ls($dirtarget, names_only=>1, no_wanted => qr/^\.+$/)};
        if ($self->_sftp->error) {
            $logger->error(
                $self->_error(
                    "ls from",  $self->remote_host, "failed with error: " . $self->_sftp->error
                )
            );
            next;
        }
        if ($dirtarget and $dirtarget ne '.' and $dirtarget ne './') {
            foreach my $file (@part) {   # we ensure full(er) path
                $file =~ /^$dirtarget\// and next;
                $logger->debug("ls_sftp: prepending $dirtarget/ to $file");
                $file = File::Spec->catdir($dirtarget, $file);
            }
        }
        if ($regex) {
            my $count = scalar(@part);
            # @part = grep {my @a = split('/',$_); scalar(@a) ? /$regex/ : ($a[-1] =~ /$regex/)} @part;
            my @bulk = @part;
            @part = grep {
                        my ($vol, $dir, $file) = File::Spec->splitpath($_);
                        $file =~ /$regex/
                    } @part;
            $logger->info("FTP ls: Glob regex($regex) matches " . scalar(@part) . " of $count files");
        } #  else {$logger->info("FTP ls: No Glob regex in '$_'.  Just a regular ls");}
        push @list, @part;
    }
    return @list;
}

sub delete_sftp {
#$sftp->remove($putfile) or die "could not remove $putfile: " . $sftp->error;
  return;
}

sub _ssh2 {
    my $self = shift;
    $self->{ssh2} and return $self->{ssh2};     # caching
    my $keys = shift;

    my $ssh2 = Net::SSH2->new();
    unless($ssh2->connect($self->remote_host)) {
        $logger->warn($self->error("SSH2 connect FAILED: $! " . join(" ", $ssh2->error)));
        return;     # we cannot connect
    }

    my $success  = 0;
    my @privates = keys %$keys;
    my $count    = scalar @privates;

    if ($count) {
        foreach (@privates) {
            if ($self->auth_ssh2($ssh2,$self->auth_ssh2_args($_,$keys->{$_}))) {
                $success++;
                last;
            }
        }
        unless ($success) {
            $logger->error(
                $self->error(
                    "All ($count) keypair(s) FAILED for " . $self->remote_host
                )
            );
            return;
        }
    } else {
        $logger->error(
            $self->error("Login FAILED for " . $self->remote_host)
        ) unless $self->auth_ssh2($ssh2, $self->auth_ssh2_args);
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
    $logger->info("*** attempting get (" . join(", ", map {$_ =~ /\S/ ? $_ : '*Object'} map {defined($_) ? $_ : '*Object'} @_) . ") with ssh keys");
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
        my ($dirpath, $regex) = $self->glob_parse($target);
        $dir = $sftp->opendir($dirpath || $target);     # Try to open it like a directory
        unless ($dir) {
            $file = $sftp->stat($target);   # Otherwise, check it like a file
            if ($file) {
                $file->{slash_path} = $self->_slash_path($target, $file->{name});     # it was a file, not a dir.  That's OK.
                push @list, $file;
            } else {
                $logger->warn($self->_error("sftp->opendir($target) failed: " . $sftp->error));
            }
            next;
        }
        my @pool = ();
        while ($file = $dir->read()) {
            $file->{slash_path} = $self->_slash_path($target, $file->{name});
            push @pool, $file;
        }
        if ($regex) {
            my $count = scalar(@pool);
            @pool = grep {$_->{name} =~ /$regex/} @pool;
            $logger->info("SSH ls: Glob regex($regex) matches " . scalar(@pool) . " of $count files"); 
        } # else { $logger->info("SSH ls: No Glob regex in '$target'.  Just a regular ls"); }
        push @list, @pool;
    }
    return @list;

}

sub delete_ssh2 {
    my $self = shift;
    my $keys = shift;
    my $file = shift;
    my $sftp = $self->_ssh2($keys)->sftp;
    return $sftp->unlink($file);
}

sub _slash_path {
    my $self = shift;
    my $dir  = shift || '.';
    my $file = shift || '';
    my ($dirpath, $regex) = $self->glob_parse($dir);
    $dir = $dirpath if $dirpath;
    return $dir . ($dir =~ /\/$/ ? '' : '/') . $file;
}

sub _ftp {
    my $self = shift;
    my %options = ();
    $self->{ftp} and return $self->{ftp};   # caching
    foreach (qw/debug port/) {
        $options{ucfirst($_)} = $self->{$_} if $self->{$_};
    }

    my $ftp = new Net::FTP($self->remote_host, %options);
    unless ($ftp) {
        $logger->error(
            $self->_error(
                "new Net::FTP('" . $self->remote_host . ", ...) FAILED: $@"
            )
        );
        return;
    }

    my @login_args = ();
    foreach (qw/remote_user remote_password remote_account/) {
        $self->{$_} or last;
        push @login_args, $self->{$_};
    }
    my $login_ok = 0;
    eval { $login_ok = $ftp->login(@login_args) };
    if ($@ or !$login_ok) {
        $logger->error(
            $self->_error(
                "failed login to", $self->remote_host, "w/ args(" .
                join(',', @login_args) . ") : $@"
            )
        ); # XXX later, maybe keep passwords out of the logs?
        return;
    }
    return $self->{ftp} = $ftp;
}

sub put_ftp {
    my $self = shift;
    my $filename;

    eval { $filename = $self->_ftp->put(@{$self->{put_args}}) };
    if ($@ or not $filename) {
        $logger->error(
            $self->_error(
                "put to", $self->remote_host, "failed with error: $@"
            )
        );
        return;
    }

    $self->remote_file($filename);
    $logger->info(
        _pkg(
            "successfully sent", $self->remote_host, $self->local_file, '-->',
            $filename
        )
    );
    return $filename;
}

sub get_ftp {
    my $self = shift;
    my $filename;

    my $remote_filename = $self->{get_args}->[0];
    eval { $filename = $self->_ftp->get(@{$self->{get_args}}) };
    if ($@ or not $filename) {
        $logger->error(
            $self->_error(
                "get from", $self->remote_host, "failed with error: $@"
            )
        );
        return;
    }
    if (!defined(${$filename->sref})) {
        # the underlying scalar is still undef, so Net::FTP must have
        # successfully retrieved an empty file... which we should skip
        $logger->error(
            $self->_error(
                "get $remote_filename from", $self->remote_host, ": remote file is zero-length"
            )
        );
        return;
    }

    $self->local_file($filename);
    $logger->info(
        _pkg(
            "successfully retrieved $filename <--", $self->remote_host . '/' .
            $self->remote_file
        )
    );
    return $self->local_file;
}

sub ls_ftp {   # returns full path like: dir/path/file.ext
    my $self = shift;
    my @list;

    foreach (@_) {
        my @part;
        my ($dirpath, $regex) = $self->glob_parse($_);
        my $dirtarget = $dirpath || $_;
        $dirtarget =~ s/\/+$//;
        eval { @part = $self->_ftp->ls($dirtarget) };      # this ls returns relative/path/filenames.  defer filename glob filtering for below.
        if ($@) {
            $logger->error(
                $self->_error(
                    "ls from",  $self->remote_host, "failed with error: $@"
                )
            );
            next;
        }
        if ($dirtarget and $dirtarget ne '.' and $dirtarget ne './' and
            $self->_ftp->dir($dirtarget)) {
            foreach my $file (@part) {   # we ensure full(er) path
                $file =~ /^$dirtarget\// and next;
                $logger->debug("ls_ftp: prepending $dirtarget/ to $file");
                $file = File::Spec->catdir($dirtarget, $file);
            }
        }
        if ($regex) {
            my $count = scalar(@part);
            # @part = grep {my @a = split('/',$_); scalar(@a) ? /$regex/ : ($a[-1] =~ /$regex/)} @part;
            my @bulk = @part;
            @part = grep {
                        my ($vol, $dir, $file) = File::Spec->splitpath($_);
                        $file =~ /$regex/
                    } @part;  
            $logger->info("FTP ls: Glob regex($regex) matches " . scalar(@part) . " of $count files");
        } #  else {$logger->info("FTP ls: No Glob regex in '$_'.  Just a regular ls");}
        push @list, @part;
    }
    return @list;
}

sub delete_ftp { 
    my $self = shift;
    my $file = shift;
    return $self->_ftp->delete($file);
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
    # let the other end know we're done.
    $self->{ssh2} and $self->{ssh2}->disconnect();
    $self->{sftp} and $self->{sftp}->disconnect();
    $self->{ftp} and $self->{ftp}->quit();
}

sub AUTOLOAD {
    my $self  = shift;
    my $class = ref($self) or croak "AUTOLOAD error: $self is not an object";
    my $name  = $AUTOLOAD;

    $name =~ s/.*://;   #   strip leading package stuff

    unless (exists $self->{_permitted}->{$name}) {
        croak "AUTOLOAD error: Cannot access '$name' field of class '$class'";
    }

    if (@_) {
        return $self->{$name} = shift;
    } else {
        return $self->{$name};
    }
}

1;

