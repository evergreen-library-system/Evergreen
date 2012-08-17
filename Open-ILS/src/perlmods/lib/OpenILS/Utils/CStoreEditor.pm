use strict; use warnings;
package OpenILS::Utils::CStoreEditor;
use OpenILS::Application::AppUtils;
use OpenSRF::AppSession;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use Data::Dumper;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw($logger);
my $U = "OpenILS::Application::AppUtils";
my %PERMS;
my $cache;
my %xact_ed_cache;

# if set, we will use this locale for all new sessions
# if unset, we rely on the existing opensrf locale propagation
our $default_locale;

our $always_xact = 0;
our $_loaded = 1;

#my %PERMS = (
#	'biblio.record_entry'	=> { update => 'UPDATE_MARC' },
#	'asset.copy'				=> { update => 'UPDATE_COPY'},
#	'asset.call_number'		=> { update => 'UPDATE_VOLUME'},
#	'action.circulation'		=> { retrieve => 'VIEW_CIRCULATIONS'},
#);

sub flush_forced_xacts {
    for my $k ( keys %xact_ed_cache ) {
        try {
            $xact_ed_cache{$k}->rollback;
        } catch Error with {
            # rollback failed
        };
        delete $xact_ed_cache{$k};
    }
}

# -----------------------------------------------------------------------------
# Export some useful functions
# -----------------------------------------------------------------------------
use vars qw(@EXPORT_OK %EXPORT_TAGS);
use Exporter;
use base qw/Exporter/;
push @EXPORT_OK, ( 'new_editor', 'new_rstore_editor' );
%EXPORT_TAGS = ( funcs => [ qw/ new_editor new_rstore_editor / ] );

sub new_editor { return OpenILS::Utils::CStoreEditor->new(@_); }

sub new_rstore_editor { 
	my $e = OpenILS::Utils::CStoreEditor->new(@_); 
	$e->app('open-ils.reporter-store');
	return $e;
}


# -----------------------------------------------------------------------------
# Log levels
# -----------------------------------------------------------------------------
use constant E => 'error';
use constant W => 'warn';
use constant I => 'info';
use constant D => 'debug';
use constant A => 'activity';



# -----------------------------------------------------------------------------
# Params include:
#	xact=><true> : creates a storage transaction
#	authtoken=>$token : the login session key
# -----------------------------------------------------------------------------
sub new {
	my( $class, %params ) = @_;
	$class = ref($class) || $class;
	my $self = bless( \%params, $class );
	$self->{checked_perms} = {};
	return $self;
}

sub DESTROY {
        my $self = shift;
        $self->reset;
        return undef;
}

sub app {
	my( $self, $app ) = @_;
	$self->{app} = $app if $app;
	$self->{app} = 'open-ils.cstore' unless $self->{app};
	return $self->{app};
}


# -----------------------------------------------------------------------------
# Log the editor metadata along with the log string
# -----------------------------------------------------------------------------
sub log {
	my( $self, $lev, $str ) = @_;
	my $s = "editor[";
    if ($always_xact) {
        $s .= "!|";
    } elsif ($self->{xact}) {
        $s .= "1|";
    } else {
	    $s .= "0|";
    }
	$s .= "0" unless $self->requestor;
	$s .= $self->requestor->id if $self->requestor;
	$s .= "]";
	$logger->$lev("$s $str");
}

# -----------------------------------------------------------------------------
# Verifies the auth token and fetches the requestor object
# -----------------------------------------------------------------------------
sub checkauth {
	my $self = shift;
	$self->log(D, "checking auth token ".$self->authtoken);

	my $content = $U->simplereq( 
		'open-ils.auth', 
		'open-ils.auth.session.retrieve', $self->authtoken, 1);

    if(!$content or $U->event_code($content)) {
        $self->event( ($content) ? $content : OpenILS::Event->new('NO_SESSION'));
        return undef;
    }

    $self->{authtime} = $content->{authtime};
	return $self->{requestor} = $content->{userobj};
}

=head1 test

sub checkauth {
	my $self = shift;
	$cache = OpenSRF::Utils::Cache->new('global') unless $cache;
	$self->log(D, "checking cached auth token ".$self->authtoken);
	my $user = $cache->get_cache("oils_auth_".$self->authtoken);
	return $self->{requestor} = $user->{userobj} if $user;
	$self->event(OpenILS::Event->new('NO_SESSION'));
	return undef;
}

=cut


# -----------------------------------------------------------------------------
# Returns the last generated event
# -----------------------------------------------------------------------------
sub event {
	my( $self, $evt ) = @_;
	$self->{event} = $evt if $evt;
	return $self->{event};
}

# -----------------------------------------------------------------------------
# Destroys the transaction and disconnects where necessary,
# then returns the last event that occurred
# -----------------------------------------------------------------------------
sub die_event {
	my $self = shift;
    my $evt = shift;
	$self->rollback;
    $self->died(1);
    $self->event($evt);
	return $self->event;
}


# -----------------------------------------------------------------------------
# Clears the last caught event
# -----------------------------------------------------------------------------
sub clear_event {
	my $self = shift;
	$self->{event} = undef;
}

sub died {
    my($self, $died) = @_;
    $self->{died} = $died if defined $died;
    return $self->{died};
}

sub authtoken {
	my( $self, $auth ) = @_;
	$self->{authtoken} = $auth if $auth;
	return $self->{authtoken};
}

sub authtime {
	my( $self, $auth ) = @_;
	$self->{authtime} = $auth if $auth;
	return $self->{authtime};
}

sub timeout {
    my($self, $to) = @_;
    $self->{timeout} = $to if defined $to;
    return defined($self->{timeout}) ? $self->{timeout} : 60;
}

# -----------------------------------------------------------------------------
# fetches the session, creating if necessary.  If 'xact' is true on this
# object, a db session is created
# -----------------------------------------------------------------------------
sub session {
	my( $self, $session ) = @_;
	$self->{session} = $session if $session;

	# sessions can stick around longer than a single request/transaction.
	# kill it if our default locale was altered since the last request
	# and it does not match the locale of the existing session.
	delete $self->{session} if
		$default_locale and
		$self->{session} and
		$self->{session}->session_locale ne $default_locale;

	if(!$self->{session}) {
		$self->{session} = OpenSRF::AppSession->create($self->app);
		$self->{session}->session_locale($default_locale) if $default_locale;

		if( ! $self->{session} ) {
			my $str = "Error creating cstore session with OpenSRF::AppSession->create()!";
			$self->log(E, $str);
			throw OpenSRF::EX::ERROR ($str);
		}

		$self->{session}->connect if $self->{xact} or $self->{connect} or $always_xact;
		$self->xact_begin if $self->{xact} or $always_xact;
	}

    $xact_ed_cache{$self->{xact_id}} = $self if $always_xact and $self->{xact_id};
	return $self->{session};
}


# -----------------------------------------------------------------------------
# Starts a storage transaction
# -----------------------------------------------------------------------------
sub xact_begin {
    my $self = shift;
    return $self->{xact_id} if $self->{xact_id};
    $self->session->connect unless $self->session->state == OpenSRF::AppSession::CONNECTED();
	$self->log(D, "starting new database transaction");
	unless($self->{xact_id}) {
	    my $stat = $self->request($self->app . '.transaction.begin');
	    $self->log(E, "error starting database transaction") unless $stat;
        $self->{xact_id} = $stat;
        if($self->authtoken) {
            if(!$self->requestor) {
                $self->checkauth;
            }
            my $user_id = undef;
            my $ws_id = undef;
            if($self->requestor) {
                $user_id = $self->requestor->id;
                $ws_id = $self->requestor->wsid;
            }
            $self->request($self->app . '.set_audit_info', $self->authtoken, $user_id, $ws_id);
        }
    }
    $self->{xact} = 1;
    return $self->{xact_id};
}

# -----------------------------------------------------------------------------
# Commits a storage transaction
# -----------------------------------------------------------------------------
sub xact_commit {
	my $self = shift;
    return unless $self->{xact_id};
	$self->log(D, "comitting db session");
	my $stat = $self->request($self->app.'.transaction.commit');
	$self->log(E, "error comitting database transaction") unless $stat;
    delete $self->{xact_id};
    delete $self->{xact};
	return $stat;
}

# -----------------------------------------------------------------------------
# Rolls back a storage stransaction
# -----------------------------------------------------------------------------
sub xact_rollback {
	my $self = shift;
    return unless $self->{session} and $self->{xact_id};
	$self->log(I, "rolling back db session");
	my $stat = $self->request($self->app.".transaction.rollback");
	$self->log(E, "error rolling back database transaction") unless $stat;
    delete $self->{xact_id};
    delete $self->{xact};
	return $stat;
}


# -----------------------------------------------------------------------------
# Savepoint functions.  If no savepoint name is provided, the same name is used 
# for each successive savepoint, in which case only the last savepoint set can 
# be released or rolled back.
# -----------------------------------------------------------------------------
sub set_savepoint {
    my $self = shift;
    my $name = shift || 'savepoint';
    return unless $self->{session} and $self->{xact_id};
	$self->log(I, "setting savepoint '$name'");
	my $stat = $self->request($self->app.".savepoint.set", $name)
	    or $self->log(E, "error setting savepoint '$name'");
    return $stat;
}

sub release_savepoint {
    my $self = shift;
    my $name = shift || 'savepoint';
    return unless $self->{session} and $self->{xact_id};
	$self->log(I, "releasing savepoint '$name'");
	my $stat = $self->request($self->app.".savepoint.release", $name)
        or $self->log(E, "error releasing savepoint '$name'");
    return $stat;
}

sub rollback_savepoint {
    my $self = shift;
    my $name = shift || 'savepoint';
    return unless $self->{session} and $self->{xact_id};
	$self->log(I, "rollback savepoint '$name'");
	my $stat = $self->request($self->app.".savepoint.rollback", $name)
        or $self->log(E, "error rolling back savepoint '$name'");
    return $stat;
}


# -----------------------------------------------------------------------------
# Rolls back the transaction and disconnects
# -----------------------------------------------------------------------------
sub rollback {
	my $self = shift;
    my $err;
    my $ret;
	try {
        $self->xact_rollback;
    } catch Error with  {
        $err = shift
    } finally {
        $ret = $self->disconnect
    };
    throw $err if ($err);
    return $ret;
}

sub disconnect {
	my $self = shift;
	$self->session->disconnect if 
        $self->{session} and 
        $self->{session}->state == OpenSRF::AppSession::CONNECTED();
    delete $self->{session};
}


# -----------------------------------------------------------------------------
# commits the db session and destroys the session
# returns the status of the commit call
# -----------------------------------------------------------------------------
sub commit {
	my $self = shift;
	return unless $self->{xact_id};
	my $stat = $self->xact_commit;
    $self->disconnect;
    return $stat;
}

# -----------------------------------------------------------------------------
# clears all object data. Does not commit the db transaction.
# -----------------------------------------------------------------------------
sub reset {
	my $self = shift;
	$self->disconnect;
	$$self{$_} = undef for (keys %$self);
}


# -----------------------------------------------------------------------------
# commits and resets
# -----------------------------------------------------------------------------
sub finish {
	my $self = shift;
    my $err;
    my $ret;
	try {
        $self->commit;
    } catch Error with  {
        $err = shift
    } finally {
        $ret = $self->reset
    };
    throw $err if ($err);
    return $ret;
}



# -----------------------------------------------------------------------------
# Does a simple storage request
# -----------------------------------------------------------------------------
sub request {
	my( $self, $method, @params ) = @_;

    my $val;
	my $err;
	my $argstr = __arg_to_string( (scalar(@params)) == 1 ? $params[0] : \@params);
	my $locale = $self->session->session_locale;

	$self->log(I, "request $locale $method $argstr");

	if( ($self->{xact} or $always_xact) and 
			$self->session->state != OpenSRF::AppSession::CONNECTED() ) {
		#$logger->error("CStoreEditor lost it's connection!!");
		throw OpenSRF::EX::ERROR ("CStore connection timed out - transaction cannot continue");
	}


	try {

        my $req = $self->session->request($method, @params);

        if($self->substream) {
            $self->log(D,"running in substream mode");
            $val = [];
            while( my $resp = $req->recv(timeout => $self->timeout) ) {
                push(@$val, $resp->content) if $resp->content and not $self->discard;
            }

        } else {
            my $resp = $req->recv(timeout => $self->timeout);
            if($req->failed) {
                $err = $resp;
		        $self->log(E, "request error $method : $argstr : $err");
            } else {
                $val = $resp->content if $resp;
            }
        }

        $req->finish;

	} catch Error with {
		$err = shift;
		$self->log(E, "request error $method : $argstr : $err");
	};

	throw $err if $err;
	return $val;
}

sub substream {
   my( $self, $bool ) = @_;
   $self->{substream} = $bool if defined $bool;
   return $self->{substream};
}

# -----------------------------------------------------------------------------
# discard response data instead of returning it to the caller.  currently only 
# works in conjunction with substream mode.  
# -----------------------------------------------------------------------------
sub discard {
   my( $self, $bool ) = @_;
   $self->{discard} = $bool if defined $bool;
   return $self->{discard};
}


# -----------------------------------------------------------------------------
# Sets / Returns the requestor object.  This is set when checkauth succeeds.
# -----------------------------------------------------------------------------
sub requestor {
	my($self, $requestor) = @_;
	$self->{requestor} = $requestor if $requestor;
	return $self->{requestor};
}



# -----------------------------------------------------------------------------
# Holds the last data received from a storage call
# -----------------------------------------------------------------------------
sub data {
	my( $self, $data ) = @_;
	$self->{data} = $data if defined $data;
	return $self->{data};
}


# -----------------------------------------------------------------------------
# True if this perm has already been checked at this org
# -----------------------------------------------------------------------------
sub perm_checked {
	my( $self, $perm, $org ) = @_;
	$self->{checked_perms}->{$org} = {}
		unless $self->{checked_perms}->{$org};
	my $checked = $self->{checked_perms}->{$org}->{$perm};
	if(!$checked) {
		$self->{checked_perms}->{$org}->{$perm} = 1;
		return 0;
	}
	return 1;
}



# -----------------------------------------------------------------------------
# Returns true if the requested perm is allowed.  If the perm check fails,
# $e->event is set and undef is returned
# The perm user is $e->requestor->id and perm org defaults to the requestor's
# ws_ou
# if perm is an array of perms, method will return true at the first allowed
# permission.  If none of the perms are allowed, the perm_failure event
# is created with the last perm to fail
# -----------------------------------------------------------------------------
my $PERM_QUERY = {
    select => {
        au => [ {
            transform => 'permission.usr_has_perm',
            alias => 'has_perm',
            column => 'id',
            params => []
        } ]
    },
    from => 'au',
    where => {},
};

my $OBJECT_PERM_QUERY = {
    select => {
        au => [ {
            transform => 'permission.usr_has_object_perm',
            alias => 'has_perm',
            column => 'id',
            params => []
        } ]
    },
    from => 'au',
    where => {},
};

sub allowed {
	my( $self, $perm, $org, $object, $hint ) = @_;
	my $uid = $self->requestor->id;
	$org ||= $self->requestor->ws_ou;

    my $perms = (ref($perm) eq 'ARRAY') ? $perm : [$perm];

    for $perm (@$perms) {
	    $self->log(I, "checking perms user=$uid, org=$org, perm=$perm");
    
        if($object) {
            my $params;
            if(ref $object) {
                # determine the ID field and json_hint from the object
                my $id_field = $object->Identity;
                $params = [$perm, $object->json_hint, $object->$id_field];
            } else {
                # we were passed an object-id and json_hint
                $params = [$perm, $hint, $object];
            }
            push(@$params, $org) if $org;
            $OBJECT_PERM_QUERY->{select}->{au}->[0]->{params} = $params;
            $OBJECT_PERM_QUERY->{where}->{id} = $uid;
            return 1 if $U->is_true($self->json_query($OBJECT_PERM_QUERY)->[0]->{has_perm});

        } else {
            $PERM_QUERY->{select}->{au}->[0]->{params} = [$perm, $org];
            $PERM_QUERY->{where}->{id} = $uid;
            return 1 if $U->is_true($self->json_query($PERM_QUERY)->[0]->{has_perm});
        }
    }

    # set the perm failure event if the permission check returned false
	my $e = OpenILS::Event->new('PERM_FAILURE', ilsperm => $perm, ilspermloc => $org);
	$self->event($e);
	return undef;
}


# -----------------------------------------------------------------------------
# Returns the list of object IDs this user has object-specific permissions for
# -----------------------------------------------------------------------------
sub objects_allowed {
    my($self, $perm, $obj_type) = @_;

    my $perms = (ref($perm) eq 'ARRAY') ? $perm : [$perm];
    my @ids;

    for $perm (@$perms) {
        my $query = {
            select => {puopm => ['object_id']},
            from => {
                puopm => {
                    ppl => {field => 'id',fkey => 'perm'}
                }
            },
            where => {
                '+puopm' => {usr => $self->requestor->id, object_type => $obj_type},
                '+ppl' => {code => $perm}
            }
        };
    
        my $list = $self->json_query($query);
        push(@ids, 0+$_->{object_id}) for @$list;
    }

   my %trim;
   $trim{$_} = 1 for @ids;
   return [ keys %trim ];
}


# -----------------------------------------------------------------------------
# checks the appropriate perm for the operation
# -----------------------------------------------------------------------------
sub _checkperm {
	my( $self, $ptype, $action, $org ) = @_;
	$org ||= $self->requestor->ws_ou;
	my $perm = $PERMS{$ptype}{$action};
	if( $perm ) {
		return undef if $self->perm_checked($perm, $org);
		return $self->event unless $self->allowed($perm, $org);
	} else {
		$self->log(I, "no perm provided for $ptype.$action");
	}
	return undef;
}



# -----------------------------------------------------------------------------
# Logs update actions to the activity log
# -----------------------------------------------------------------------------
sub log_activity {
	my( $self, $type, $action, $arg ) = @_;
	my $str = "$type.$action";
	$str .= _prop_string($arg);
	$self->log(A, $str);
}



sub _prop_string {
	my $obj = shift;
	my @props = $obj->properties;
	my $str = "";
	for(@props) {
		my $prop = $obj->$_() || "";
		$prop = substr($prop, 0, 128) . "..." if length $prop > 131;
		$str .= " $_=$prop";
	}
	return $str;
}


sub __arg_to_string {
	my $arg = shift;
	return "" unless defined $arg;
	if( UNIVERSAL::isa($arg, "Fieldmapper") ) {
        my $idf = $arg->Identity;
		return (defined $arg->$idf) ? $arg->$idf : '<new object>';
	}
	return OpenSRF::Utils::JSON->perl2JSON($arg);
	return "";
}


# -----------------------------------------------------------------------------
# This does the actual storage query.
#
# 'search' calls become search_where calls and $arg can be a search hash or
# an array-ref of storage search options.  
#
# 'retrieve' expects an id
# 'update' expects an object
# 'create' expects an object
# 'delete' expects an object
#
# All methods return true on success and undef on failure.  On failure, 
# $e->event is set to the generated event.  
# Note: this method assumes that updating a non-changed object and 
# thereby receiving a 0 from storage, is a successful update.  
#
# The method will therefore return true so the caller can just do 
# $e->update_blah($x) or return $e->event;
# The true value returned from storage for all methods will be stored in 
# $e->data, until the next method is called.
#
# not-found events are generated on retrieve and serach methods.
# action=search methods will return [] (==true) if no data is found.  If the
# caller is interested in the not found event, they can do:  
# return $e->event unless @$results; 
# -----------------------------------------------------------------------------
sub runmethod {
	my( $self, $action, $type, $arg, $options ) = @_;

   $options ||= {};

	if( $action eq 'retrieve' ) {
		if(! defined($arg) ) {
			$self->log(W,"$action $type called with no ID...");
			$self->event(_mk_not_found($type, $arg));
			return undef;
		} elsif( ref($arg) =~ /Fieldmapper/ ) {
			$self->log(D,"$action $type called with an object.. attempting Identity retrieval..");
            my $idf = $arg->Identity;
			$arg = $arg->$idf;
		}
	}

	my @arg = ( ref($arg) eq 'ARRAY' ) ? @$arg : ($arg);
	my $method = $self->app.".direct.$type.$action";

	if( $action eq 'search' ) {
		$method .= '.atomic';

	} elsif( $action eq 'batch_retrieve' ) {
		$action = 'search';
		$method =~ s/batch_retrieve/search/o;
		$method .= '.atomic';
		my $tt = $type;
		$tt =~ s/\./::/og;
		my $fmobj = "Fieldmapper::$tt";
		my $ident_field = $fmobj->Identity;

		if (ref $arg[0] eq 'ARRAY') {
			# $arg looks like: ([1, 2, 3], {search_args})
			@arg = ( { $ident_field => $arg[0] }, @arg[1 .. $#arg] );
		} else {
			# $arg looks like: [1, 2, 3]
			@arg = ( { $ident_field => $arg } );
		}

	} elsif( $action eq 'retrieve_all' ) {
		$action = 'search';
		$method =~ s/retrieve_all/search/o;
		my $tt = $type;
		$tt =~ s/\./::/og;
		my $fmobj = "Fieldmapper::$tt";
		@arg = ( { $fmobj->Identity => { '!=' => undef } } );
		$method .= '.atomic';
	}

	$method =~ s/search/id_list/o if $options->{idlist};

    $method =~ s/\.atomic$//o if $self->substream($$options{substream} || 0);
    $self->timeout($$options{timeout});
    $self->discard($$options{discard});

	# remove any stale events
	$self->clear_event;

	if( $action eq 'update' or $action eq 'delete' or $action eq 'create' ) {
		if(!($self->{xact} or $always_xact)) {
			$logger->error("Attempt to update DB while not in a transaction : $method");
			throw OpenSRF::EX::ERROR ("Attempt to update DB while not in a transaction : $method");
		}
		$self->log_activity($type, $action, $arg);
	}

	if($$options{checkperm}) {
		my $a = ($action eq 'search') ? 'retrieve' : $action;
		my $e = $self->_checkperm($type, $a, $$options{permorg});
		if($e) {
			$self->event($e);
			return undef;
		}
	}

	my $obj; 
	my $err = '';

	try {
		$obj = $self->request($method, @arg);
	} catch Error with { $err = shift; };
	

	if(!defined $obj) {
		$self->log(I, "request returned no data : $method");

		if( $action eq 'retrieve' ) {
			$self->event(_mk_not_found($type, $arg));

		} elsif( $action eq 'update' or 
				$action eq 'delete' or $action eq 'create' ) {
			my $evt = OpenILS::Event->new(
				'DATABASE_UPDATE_FAILED', payload => $arg, debug => "$err" );
			$self->event($evt);
		}

		if( $err ) {
			$self->event( 
				OpenILS::Event->new( 'DATABASE_QUERY_FAILED', 
					payload => $arg, debug => "$err" ));
			return undef;
		}

		return undef;
	}

	if( $action eq 'create' and $obj == 0 ) {
		my $evt = OpenILS::Event->new(
			'DATABASE_UPDATE_FAILED', payload => $arg, debug => "$err" );
		$self->event($evt);
		return undef;
	}

	# If we havn't dealt with the error in a nice way, go ahead and throw it
	if( $err ) {
		$self->event( 
			OpenILS::Event->new( 'DATABASE_QUERY_FAILED', 
				payload => $arg, debug => "$err" ));
		return undef;
	}

	if( $action eq 'search' ) {
		$self->log(I, "$type.$action : returned ".scalar(@$obj). " result(s)");
		$self->event(_mk_not_found($type, $arg)) unless @$obj;
	}

	if( $action eq 'create' ) {
        my $idf = $obj->Identity;
		$self->log(I, "created a new $type object with Identity " . $obj->$idf);
		$arg->$idf($obj->$idf);
	}

	$self->data($obj); # cache the data for convenience

	return ($obj) ? $obj : 1;
}


sub _mk_not_found {
	my( $type, $arg ) = @_;
	(my $t = $type) =~ s/\./_/og;
	$t = uc($t);
	return OpenILS::Event->new("${t}_NOT_FOUND", payload => $arg);
}



# utility method for loading
sub __fm2meth { 
	my $str = shift;
	my $sep = shift;
	$str =~ s/Fieldmapper:://o;
	$str =~ s/::/$sep/g;
	return $str;
}


# -------------------------------------------------------------
# Load up the methods from the FM classes
# -------------------------------------------------------------

sub init {
    no warnings;    #  Here we potentially redefine subs via eval
    my $map = $Fieldmapper::fieldmap;
    for my $object (keys %$map) {
        my $obj  = __fm2meth($object, '_');
        my $type = __fm2meth($object, '.');
        foreach my $command (qw/ update retrieve search create delete batch_retrieve retrieve_all /) {
            eval "sub ${command}_$obj {return shift()->runmethod('$command', '$type', \@_);}\n";
        }
        # TODO: performance test against concatenating a big string of all the subs and eval'ing only ONCE.
    }
}

init();  # Add very many subs to this namespace

sub json_query {
    my( $self, $arg, $options ) = @_;
    $options ||= {};
	my @arg = ( ref($arg) eq 'ARRAY' ) ? @$arg : ($arg);
    my $method = $self->app.'.json_query.atomic';
    $method =~ s/\.atomic$//o if $self->substream($$options{substream} || 0);

    $self->timeout($$options{timeout});
    $self->discard($$options{discard});
	$self->clear_event;
    my $obj;
    my $err;
    
    try {
        $obj = $self->request($method, @arg);
    } catch Error with { $err = shift; };

    if( $err ) {
        $self->event(
            OpenILS::Event->new( 'DATABASE_QUERY_FAILED',
            payload => $arg, debug => "$err" ));
        return undef;
    }

    $self->log(I, "json_query : returned ".scalar(@$obj). " result(s)") if (ref($obj));
    return $obj;
}



1;


