use strict; use warnings;
package OpenILS::Utils::CStoreEditor;
use OpenILS::Application::AppUtils;
use OpenSRF::AppSession;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use Data::Dumper;
use JSON;
use OpenSRF::Utils::Logger qw($logger);
my $U = "OpenILS::Application::AppUtils";
my %PERMS;


# -----------------------------------------------------------------------------
# Export some useful functions
# -----------------------------------------------------------------------------
use vars qw(@EXPORT_OK %EXPORT_TAGS);
use Exporter;
use base qw/Exporter/;
push @EXPORT_OK, 'new_editor';
%EXPORT_TAGS = ( funcs => [ qw/ new_editor / ] );

sub new_editor { return OpenILS::Utils::CStoreEditor->new(@_); }


# -----------------------------------------------------------------------------
# These need to be auto-generated
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

# -----------------------------------------------------------------------------
# Log the editor metadata along with the log string
# -----------------------------------------------------------------------------
sub log {
	my( $self, $lev, $str ) = @_;
	my $s = "editor[";
	$s .= "0|" unless $self->{xact};
	$s .= "1|" if $self->{xact};
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
	my ($reqr, $evt) = $U->checkses($self->authtoken);
	$self->event($evt) if $evt;
	return $self->{requestor} = $reqr;
}


# -----------------------------------------------------------------------------
# Returns the last generated event
# -----------------------------------------------------------------------------
sub event {
	my( $self, $evt ) = @_;
	$self->{event} = $evt if $evt;
	return $self->{event};
}

# -----------------------------------------------------------------------------
# Clears the last caught event
# -----------------------------------------------------------------------------
sub clear_event {
	my $self = shift;
	$self->{event} = undef;
}

sub authtoken {
	my( $self, $auth ) = @_;
	$self->{authtoken} = $auth if $auth;
	return $self->{authtoken};
}

# -----------------------------------------------------------------------------
# fetches the session, creating if necessary.  If 'xact' is true on this
# object, a db session is created
# -----------------------------------------------------------------------------
sub session {
	my( $self, $session ) = @_;
	$self->{session} = $session if $session;

	if(!$self->{session}) {
		$self->{session} = OpenSRF::AppSession->create('open-ils.cstore');

		if( ! $self->{session} ) {
			my $str = "Error creating storage session with OpenSRF::AppSession->create()!";
			$self->log(E, $str);
			throw OpenSRF::EX::ERROR ($str);
		}

		$self->{session}->connect if $self->{xact} or $self->{connect};
		$self->xact_start if $self->{xact};
	}
	return $self->{session};
}


# -----------------------------------------------------------------------------
# Starts a storage transaction
# -----------------------------------------------------------------------------
sub xact_start {
	my $self = shift;
	$self->log(D, "starting new db session");
	my $stat = $self->request('open-ils.cstore.transaction.begin');
	$self->log(E, "error starting database transaction") unless $stat;
	return $stat;
}

# -----------------------------------------------------------------------------
# Commits a storage transaction
# -----------------------------------------------------------------------------
sub xact_commit {
	my $self = shift;
	$self->log(D, "comitting db session");
	my $stat = $self->request('open-ils.cstore.transaction.commit');
	$self->log(E, "error comitting database transaction") unless $stat;
	return $stat;
}

# -----------------------------------------------------------------------------
# Rolls back a storage stransaction
# -----------------------------------------------------------------------------
sub xact_rollback {
	my $self = shift;
	$self->log(I, "rolling back db session");
	return $self->request("open-ils.cstore.transaction.rollback");
}


# -----------------------------------------------------------------------------
# commits the db session and destroys the session
# -----------------------------------------------------------------------------
sub commit {
	my $self = shift;
	return unless $self->{xact};
	$self->xact_commit;
	$self->session->disconnect;
	$self->{session} = undef;
}

# -----------------------------------------------------------------------------
# clears all object data. Does not commit the db transaction.
# -----------------------------------------------------------------------------
sub reset {
	my $self = shift;
	$self->session->disconnect if $self->{session};
	$$self{$_} = undef for (keys %$self);
}


# -----------------------------------------------------------------------------
# commits and resets
# -----------------------------------------------------------------------------
sub finish {
	my $self = shift;
	$self->commit;
	$self->reset;
}



# -----------------------------------------------------------------------------
# Does a simple storage request
# -----------------------------------------------------------------------------
sub request {
	my( $self, $method, @params ) = @_;

	my $val;
	my $err;
	my $argstr = __arg_to_string( (scalar(@params)) == 1 ? $params[0] : \@params);

	$self->log(I, "request $method : $argstr");
	
	try {
		$val = $self->session->request($method, @params)->gather(1);

	} catch Error with {
		$err = shift;
		$self->log(E, "request error $method : $argstr : $err");
	};

	throw $err if $err;
	return $val;
}


# -----------------------------------------------------------------------------
# Sets / Returns the requstor object.  This is set when checkauth succeeds.
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
# If this perm at the given org has already been verified, true is returned
# and the perm is not re-checked
# -----------------------------------------------------------------------------
sub allowed {
	my( $self, $perm, $org ) = @_;
	my $uid = $self->requestor->id;
	$org ||= $self->requestor->ws_ou;
	$self->log(I, "checking perms user=$uid, org=$org, perm=$perm");
	return 1 if $self->perm_checked($perm, $org); 
	return $self->checkperm($uid, $org, $perm);
}

sub checkperm {
	my($self, $userid, $org, $perm) = @_;
	my $s = $U->storagereq(
		"open-ils.storage.permission.user_has_perm", $userid, $perm, $org );

	if(!$s) {
		my $e = OpenILS::Event->new('PERM_FAILURE', ilsperm => $perm, ilspermloc => $org);
		$self->event($e);
		return undef;
	}

	return 1;
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
		$self->log(E, "no perm provided for $ptype.$action");
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
	return $arg->id if UNIVERSAL::isa($arg, "Fieldmapper");
	return JSON->perl2JSON($arg);
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

	my @arg = ($arg);
	my $method = "open-ils.cstore.direct.$type.$action";

	if( $action eq 'search' ) {
		$method = "$method.atomic";
		@arg = @$arg if ref($arg) eq 'ARRAY';

	} elsif( $action eq 'batch_retrieve' ) {
		$action = 'search';
		@arg = ( { id => $arg } );
		$method =~ s/batch_retrieve/search/o;
		$method = "$method.atomic";

	} elsif( $action eq 'retrieve_all' ) {
		$action = 'search';
		$method =~ s/retrieve_all/search/o;
		@arg = ( { id => { '!=' => 0 } } );
		$method = "$method.atomic";
	}

	$method =~ s/search/id_list/o if $options->{idlist};

	# remove any stale events
	$self->clear_event;

	if( $action eq 'update' or $action eq 'delete' or $action eq 'create' ) {
		if(!$self->{xact}) {
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
	my $err;

	try {
		$obj = $self->request($method, @arg);
	} catch Error with { $err = shift; };
	

	if(!defined $obj) {
		$self->log(I, "request returned no data");

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

	if( $action eq 'search' or $action eq 'batch_retrieve' or $action eq 'retrieve_all') {
		$self->log(I, "$type.$action : returned ".scalar(@$obj). " result(s)");
		$self->event(_mk_not_found($type, $arg)) unless @$obj;
	}

	$arg->id($obj) if $action eq 'create'; # grabs the id on create
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
my $map = $Fieldmapper::fieldmap;
for my $object (keys %$map) {
	my $obj = __fm2meth($object,'_');
	my $type = __fm2meth($object, '.');

	my $update = "update_$obj";
	my $updatef = 
		"sub $update {return shift()->runmethod('update', '$type', \@_);}";
	eval $updatef;

	my $retrieve = "retrieve_$obj";
	my $retrievef = 
		"sub $retrieve {return shift()->runmethod('retrieve', '$type', \@_);}";
	eval $retrievef;

	my $search = "search_$obj";
	my $searchf = 
		"sub $search {return shift()->runmethod('search', '$type', \@_);}";
	eval $searchf;

	my $create = "create_$obj";
	my $createf = 
		"sub $create {return shift()->runmethod('create', '$type', \@_);}";
	eval $createf;

	my $delete = "delete_$obj";
	my $deletef = 
		"sub $delete {return shift()->runmethod('delete', '$type', \@_);}";
	eval $deletef;

	my $bretrieve = "batch_retrieve_$obj";
	my $bretrievef = 
		"sub $bretrieve {return shift()->runmethod('batch_retrieve', '$type', \@_);}";
	eval $bretrievef;

	my $retrieveall = "retrieve_all_$obj";
	my $retrieveallf = 
		"sub $retrieveall {return shift()->runmethod('retrieve_all', '$type', \@_);}";
	eval $retrieveallf;


}



1;


