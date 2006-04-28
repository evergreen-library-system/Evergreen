use strict; use warnings;
package OpenILS::Utils::Editor;
use OpenILS::Application::AppUtils;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw($logger);
my $U = "OpenILS::Application::AppUtils";


my %PERMS = (
	'biblio.record_entry'	=> { update => 'UPDATE_MARC' },
	'asset.copy'				=> { update => 'UPDATE_COPY'},
	'asset.call_number'		=> { update => 'UPDATE_VOLUME'},
);


sub new {
	my( $class, %params ) = @_;
	$class = ref($class) || $class;
	return bless( \%params, $class );
}

# fetches the session, creating if necessary
sub session {
	my( $self, $session ) = @_;
	$self->{session} = $session if $session;
	$self->{session} = $U->start_db_session unless $self->{session};
	return $self->{session};
}

# commits the db session
sub commit {
	my $self = shift;
	$logger->info("editor: committing session");
	$U->commit_db_session( $self->session );
}

# clears state data, but does not commit the db transaction
sub reset {
	my $self = shift;
	$logger->debug("editor: cleaning up");
	$$self{$_} = undef for (keys %$self);
}

# commits and resets
sub finish {
	my $self = shift;
	$self->commit;
	$self->reset;
}

sub setperm {
	my( $self, $type, $perm) = @_;
}


# -------------------------------------------------------------
# Actually performs the perm check
# -------------------------------------------------------------
sub checkperms {
	my($self, $uid, $org, @perms) = @_;
	$logger->info("editor: checking perms user=$uid, org=$org, perms=@perms");
	for my $type (@perms) {
		my $success = $self->session->request(
			"open-ils.storage.permission.user_has_perm", 
			$uid, $type, $org )->gather(1);
		return OpenILS::Event->new( 'PERM_FAILURE', 
			ilsperm => $type, ilspermloc => $org ) unless $success;
	}
	return undef;
}


# -------------------------------------------------------------
# checks the appropriate perm for the operations if that perm
# hasn't already been checked for this session
# -------------------------------------------------------------
sub checkperm {
	my( $self, $ptype, $action, $org ) = @_;
	$org ||= $self->{requestor}->ws_ou;
	my $perm = $PERMS{$ptype}{$action};
	if( $perm ) {
		if( !$self->{$perm} ) {
			my $evt = $self->checkperms(
				$self->{requestor}->id, $org, $perm );
			return $evt if $evt;
			$self->{$perm} = 1;
		}
	}
	return undef;
}



# -------------------------------------------------------------
# does the object updating
# -------------------------------------------------------------
sub _update_method {
	my( $self, $type, $obj, $params ) = @_;
	my $method = "open-ils.storage.direct.$type.update";
	$logger->info("editor: updating $type ".$obj->id);
	my $evt = $self->checkperm(
		$type, 'update', $$params{org}) if $$params{checkperm};
	return $evt if $evt;
	return $U->DB_UPDATE_FAILED($obj) unless 
		$self->session->request($method, $obj)->gather(1);
	return undef;
}


# -------------------------------------------------------------
# does the actual fetching by id
# -------------------------------------------------------------
sub _retrieve_method {
	my( $self, $type, $id, $params ) = @_;
	my $method = "open-ils.storage.direct.$type.retrieve";
	$logger->info("editor: retrieving $type ".$id);
	my $evt = $self->checkperm(
		$type, 'retrieve', $$params{org}) if $$params{checkperm};
	return $self->session->request($method, $id)->gather(1);
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
		"sub $update {return shift()->_update_method('$type', \@_);}";
	eval $updatef;

	my $retrieve = "retrieve_$obj";
	my $retrievef = 
		"sub $retrieve {return shift()->_retrieve_method('$type', \@_);}";
	eval $retrievef;
}



1;


