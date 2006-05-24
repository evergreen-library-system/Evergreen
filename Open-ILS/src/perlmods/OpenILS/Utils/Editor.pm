use strict; use warnings;
package OpenILS::Utils::Editor;
use OpenILS::Application::AppUtils;
use OpenSRF::AppSession;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use Data::Dumper;
use OpenSRF::Utils::Logger qw($logger);
my $U = "OpenILS::Application::AppUtils";


# -----------------------------------------------------------------------------
# Export some useful functions
# -----------------------------------------------------------------------------
use vars qw(@EXPORT_OK %EXPORT_TAGS);
use Exporter;
use base qw/Exporter/;
push @EXPORT_OK, 'new_editor';
%EXPORT_TAGS = ( funcs => [ qw/ new_editor / ] );

sub new_editor { return OpenILS::Utils::Editor->new(@_); }


# -----------------------------------------------------------------------------
# These need to be auto-generated
# -----------------------------------------------------------------------------
my %PERMS = (
	'biblio.record_entry'	=> { update => 'UPDATE_MARC' },
	'asset.copy'				=> { update => 'UPDATE_COPY'},
	'asset.call_number'		=> { update => 'UPDATE_VOLUME'},
	'action.circulation'		=> { retrieve => 'VIEW_CIRCULATIONS'},
);

my $logstr;
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
	$logstr = "editor [0";
	$logstr = "editor [1" if $self->{xact};
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
		$self->{session} = OpenSRF::AppSession->create('open-ils.storage');

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
	my $stat = $self->request('open-ils.storage.transaction.begin');
	$self->log(E, "error starting database transaction") unless $stat;
	return $stat;
}

# -----------------------------------------------------------------------------
# Commits a storage transaction
# -----------------------------------------------------------------------------
sub xact_commit {
	my $self = shift;
	$self->log(D, "comitting db session");
	my $stat = $self->request('open-ils.storage.transaction.commit');
	$self->log(E, "error comitting database transaction") unless $stat;
	return $stat;
}

# -----------------------------------------------------------------------------
# Rolls back a storage stransaction
# -----------------------------------------------------------------------------
sub xact_rollback {
	my $self = shift;
	$self->log(I, "rolling back db session");
	return $self->request("open-ils.storage.transaction.rollback");
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

	try {
		$val = $self->session->request($method, @params)->gather(1);

	} catch Error with {
		my $err = shift;
		$self->log(E, "request error $method=@params : $err");
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

	my $s = $self->request(
		"open-ils.storage.permission.user_has_perm", $uid, $perm, $org );

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
sub checkperm {
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

sub _hash_to_string {
	my $h = shift;
	my $str = "";
	$str .= " $_=".$h->{$_} for keys %$h;
	return $str;
}

sub _arg_to_string {
	my( $action, $arg ) = @_;
	return "" unless $arg;
	return $arg->id if UNIVERSAL::isa($arg, "Fieldmapper");
	return _hash_to_string($arg) if ref $arg eq 'HASH'; # search
	return "[@$arg]" if ref $arg eq 'ARRAY';
	return $arg; # retrieve
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
	my $method = "open-ils.storage.direct.$type.$action";
	my $argstr = _arg_to_string($action, $arg);

	if( $action eq 'search' ) {
		$method =~ s/search/search_where/o;
		$method =~ s/direct/id_list/o if $options->{idlist};
		$method = "$method.atomic";
		@arg = @$arg if ref($arg) eq 'ARRAY';

	} elsif( $action eq 'batch_retrieve' ) {
		$method =~ s/batch_retrieve/batch.retrieve/o;
		$method = "$method.atomic";
		@arg = @$arg if ref($arg) eq 'ARRAY';

	} elsif( $action eq 'retrieve_all' ) {
		$method =~ s/retrieve_all/retrieve.all.atomic/o;
	}

	# remove any stale events
	$self->clear_event;

	$self->log(I, "$type.$action : $argstr");
	if( $action eq 'update' or $action eq 'delete' or $action eq 'create' ) {
		$self->log_activity($type, $action, $arg);
	}

	if($$options{checkperm}) {
		my $a = ($action eq 'search' or 
			$action eq 'batch_retrieve' or $action eq 'retrieve_all') ? 'retrieve' : $action;
		my $e = $self->checkperm($type, $a, $$options{permorg});
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

		return undef;
	}

	if( $action eq 'create' and $obj == 0 ) {
		my $evt = OpenILS::Event->new(
			'DATABASE_UPDATE_FAILED', payload => $arg, debug => "$err" );
		$self->event($evt);
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


