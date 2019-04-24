#!/usr/bin/perl
use strict; use warnings;
use CGI;
use OpenSRF::Utils::JSON;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::EX qw/:try/;
use Data::Dumper;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils qw/:daemon/;
use OpenILS::Utils::DateTime qw/clean_ISO8601/;
use OpenILS::Utils::OfflineStore;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils;
use DateTime;
use DateTime::Format::ISO8601;

use DBI;
$DBI::trace = 1;

my $U = "OpenILS::Application::AppUtils";
my $DB = "OpenILS::Utils::OfflineStore";
my $SES = "${DB}::Session";
my $SCRIPT = "OpenILS::Utils::OfflineStore::Script";
my $user_groups;

# Used by the functionality that produces SKIP_ASSET_CHANGED events
my %seen_barcode = ();
my %skip_barcode_for_status_changed = ();

# --------------------------------------------------------------------
# Load the config
# --------------------------------------------------------------------
our %config;
do '##CONFIG##/offline-config.pl';


my $cgi			= new CGI;
my $basedir		= $config{base_dir} || die "Offline config error: no base_dir defined\n";
my $bootstrap	= $config{bootstrap} || die "Offline config error: no bootstrap defined\n";
my $webclient	= $cgi->param('wc');
my $wsname		= $cgi->param('ws');
my $org			= $cgi->param('org');
my $authtoken	= $cgi->param('ses') || "";
my $seskey		= $cgi->param('seskey');
my $action		= $cgi->param('action'); # - create, load, execute, status
my $requestor; 
my $wsobj;
my $orgobj;
my $evt;


&ol_init;
&ol_runtime_init;
&ol_do_action;


# --------------------------------------------------------------------
# Set it all up
# This function should behave as a child_init might behave in case 
# this is moved to mod_perl
# --------------------------------------------------------------------
sub ol_init {
	$DB->DBFile($config{dsn}, $config{usr}, $config{pw});
	ol_connect();
}

sub ol_connect {
	OpenSRF::System->bootstrap_client(config_file => $bootstrap ); 
	Fieldmapper->import(IDL => 
		OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

}


sub _ol_debug_params {
	my $s = "";
	my @params = $cgi->param;
	@params = sort { $a cmp $b } @params;
	$s .= "$_=" . $cgi->param($_) . "\n" for @params;
	$s =~ s/\n$//o;
	warn '-'x60 ."\n$s\n";
}


# --------------------------------------------------------------------
# Finds the requestor and other info specific to this request
# --------------------------------------------------------------------
sub ol_runtime_init {

	# fetch the requestor object
	($requestor, $evt) = $U->checkses($authtoken);
	ol_handle_result($evt) if $evt;

	# try the param, the workstation, and finally the user's ws org
	if(!$org) { 
		$wsobj = ol_fetch_workstation($wsname);
		$org = $wsobj->owning_lib if $wsobj;
		$org = $requestor->ws_ou unless $org;
		ol_handle_result(OpenILS::Event->new('OFFLINE_NO_ORG')) unless $org;
	}

    $user_groups = $U->simplereq(
        'open-ils.actor', 'open-ils.actor.groups.retrieve');
}


# --------------------------------------------------------------------
# Runs the requested action
# --------------------------------------------------------------------
sub ol_do_action {

	my $payload;

	if( $action eq 'create' ) {
		
		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_UPLOAD');
		ol_handle_result($evt) if $evt;
		$payload = ol_create_session();

	} elsif( $action eq 'load' ) {

		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_UPLOAD');
		ol_handle_result($evt) if $evt;
		$payload = ol_load();

	} elsif( $action eq 'execute' ) {

		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_EXECUTE');
		ol_handle_result($evt) if $evt;
		$payload = ol_execute();

	} elsif( $action eq 'status' ) {

		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_VIEW');
		ol_handle_result($evt) if $evt;
		$payload = ol_status();
	}

	ol_handle_event('SUCCESS', payload => $payload );
}


# --------------------------------------------------------------------
# Creates a new session
# --------------------------------------------------------------------
sub ol_create_session {

	my $desc = $cgi->param('desc') || "";
	$seskey = time . "_${$}_" . int(rand() * 1000);

	$logger->debug("offline: user ".$requestor->id.
		" creating new session with key $seskey and description $desc");

	$SES->create(
		{	
			key				=> $seskey,
			org				=> $org,
			description		=> $desc,
			creator			=> $requestor->id,
			create_time		=> CORE::time(), 
			num_complete	=> 0,
		} 
	);

	return $seskey;
}


# --------------------------------------------------------------------
# Holds the meta-info for a script file
# --------------------------------------------------------------------
sub ol_create_script {
	my $count = shift;

	my $session = ol_find_session($seskey);
	my $delta = $cgi->param('delta') || 0;

	my $script = $session->add_to_scripts( 
		{
			requestor	=> $requestor->id,
			create_time	=> CORE::time,
			workstation	=> $wsname,
			logfile		=> "$basedir/pending/$org/$seskey/$wsname.log",
			time_delta	=> $delta,
			count			=> $count,
		}
	);
}

# --------------------------------------------------------------------
# Finds the current session in the db
# --------------------------------------------------------------------
sub ol_find_session {
	my $ses = $SES->retrieve($seskey);
	ol_handle_event('OFFLINE_INVALID_SESSION', payload => $seskey) unless $ses;
	return $ses;
}

# --------------------------------------------------------------------
# Finds a script object in the DB based on workstation and seskey
# --------------------------------------------------------------------
sub ol_find_script {
	my $ws = shift || $wsname;
	my $sk = shift || $seskey;
	my ($script) = $SCRIPT->search( session => $seskey, workstation => $ws );
	return $script;
}

# --------------------------------------------------------------------
# Creates a new script in the database and loads the new script file
# --------------------------------------------------------------------
sub ol_load {

	my $session = ol_find_session;
	my $handle	= $cgi->upload('file');
	my $outdir	= "$basedir/pending/$org/$seskey";
	my $outfile = "$outdir/$wsname.log";

	ol_handle_event('OFFLINE_SESSION_FILE_EXISTS') if ol_find_script();
	ol_handle_event('OFFLINE_SESSION_ACTIVE') if $session->in_process;
	ol_handle_event('OFFLINE_SESSION_COMPLETE') if $session->end_time;

	qx/mkdir -p $outdir/;
	my $x = 0;
	open(FILE, ">>$outfile") or ol_handle_event('OFFLINE_FILE_ERROR');
	while( <$handle> ) { print FILE; $x++;}
	close(FILE);

	ol_create_script($x);

	return undef;
}


# --------------------------------------------------------------------
sub ol_handle_result {
	my $obj = shift;
	my $json = OpenSRF::Utils::JSON->perl2JSON($obj);

	# Clear this so it's not remembered
	$evt = undef;

	if( $cgi->param('html')) {
		my $html = "<html><body onload='xulG.handle_event($json)'></body></html>";
		print "content-type: text/html\n\n";
		print "$html\n";

	} else {

		print "content-type: text/plain\n\n";
		print "$json\n";
	}

	exit(0);
}

# --------------------------------------------------------------------
sub ol_handle_event {
	my( $evt, @args ) = @_;
	ol_handle_result(OpenILS::Event->new($evt, @args));
}


# --------------------------------------------------------------------
sub ol_flesh_session {
	my $session = shift;
	my %data;

	map { $data{$_} = $session->$_ } $session->columns;
	$data{scripts} = [];

	for my $script ($session->scripts) {
		my %sdata;
		map { $sdata{$_} = $script->$_ } $script->columns;

		# the client doesn't need this info
		delete $sdata{session};
		delete $sdata{id};
		delete $sdata{logfile};

		push( @{$data{scripts}}, \%sdata );
	}

	return \%data;
}


# --------------------------------------------------------------------
# Returns various information on the sessions and scripts
# --------------------------------------------------------------------
sub ol_status {

	my $type = $cgi->param('status_type') || "scripts";

	# --------------------------------------------------------------------
	# Returns info on every script upload attached to the current session
	# --------------------------------------------------------------------
	if( $type eq 'scripts' ) {
		my $session = ol_find_session();
		ol_handle_result(ol_flesh_session($session));


	# --------------------------------------------------------------------
	# Returns all scripts and sessions for the given org
	# --------------------------------------------------------------------
	} elsif( $type eq 'sessions' ) {
		my @sessions = $SES->search( org => $org );

		# can I do this in the DB without raw SQL?
		@sessions = sort { $a->create_time <=> $b->create_time } @sessions; 
		my @data;
		push( @data, ol_flesh_session($_) ) for @sessions;
		ol_handle_result(\@data);


	# --------------------------------------------------------------------
	# Returns total commands and completed commands counts
	# --------------------------------------------------------------------
	} elsif( $type eq 'summary' ) {
		my $session = ol_find_session();

		$logger->debug("offline: retrieving summary info ".
			"for session ".$session->key." with completed=".$session->num_complete);

		my $count = 0;
		$count += $_->count for ($session->scripts);
		ol_handle_result(
			{ total => $count, num_complete => $session->num_complete });



	# --------------------------------------------------------------------
	# Returns the list of non-SUCCESS events that have occurred so far for 
	# this set of commands
	# --------------------------------------------------------------------
	} elsif( $type eq 'exceptions' ) {

		my $session = ol_find_session();
		my $resfile = "$basedir/pending/$org/$seskey/results";
		if( $session->end_time ) {
			$resfile = "$basedir/archive/$org/$seskey/results";
		}
		my $data = ol_file_to_perl($resfile);
        my $data2 = [];
        for my $d (@$data) {
            my $evt = $d->{event};
            $evt = $evt->[0] if ref $evt eq 'ARRAY';
            push(@$data2, $d) if $evt->{ilsevent} ne '0';
        }
		#$data = [ grep { $_->{event}->{ilsevent} ne '0' } @$data ];
		ol_handle_result($data2);
	}
}


sub ol_fetch_workstation {
	my $name = shift;
	$logger->debug("offline: Fetching workstation $name");
	my $ws = $U->storagereq(
		'open-ils.storage.direct.actor.workstation.search.name', $name);
	ol_handle_result(OpenILS::Event->new('ACTOR_WORKSTATION_NOT_FOUND')) unless $ws;
	return $ws;
}




# --------------------------------------------------------------------
# Sorts the script commands then forks a child to executes them.
# --------------------------------------------------------------------
sub ol_execute {

	my $session = ol_find_session();
	ol_handle_event('OFFLINE_SESSION_ACTIVE') if $session->in_process;
	ol_handle_event('OFFLINE_SESSION_COMPLETE') if $session->end_time;

	my $commands = ol_collect_commands();

	# --------------------------------------------------------------------
	# Note that we must disconnect from opensrf before forking or the 
	# connection will be borked...
	# --------------------------------------------------------------------
	OpenSRF::Transport::PeerHandle->retrieve->disconnect;
	$DB->disconnect;


	if( safe_fork() ) {

		# --------------------------------------------------------------------
		# Tell the client all is well
		# --------------------------------------------------------------------
		ol_handle_event('SUCCESS'); # - this exits

	} else {


		# --------------------------------------------------------------------
		# close stdout/stderr or apache will wait on the child to finish
		# --------------------------------------------------------------------
		close(STDOUT);
		close(STDERR);

		$logger->debug("offline: child $$ processing data...");

		# --------------------------------------------------------------------
		# The child re-connects to the opensrf network and processes
		# the script requests 
		# --------------------------------------------------------------------
		OpenSRF::System->bootstrap_client(config_file => $bootstrap);
	
		try {

			#use Class::DBI
			#Class::DBI->autoupdate(1);

			$DB->autoupdate(1);

			my $sesion = ol_find_session();
			$session->in_process(1);
			ol_process_commands($session, $commands);
			ol_archive_files($session);

		} catch Error with {
			my $e = shift;
			$logger->error("offline: child process error $e");
		};
	}
}

sub ol_file_to_perl {
	my $fname = shift;
	open(F, "$fname") or ol_handle_event('OFFLINE_FILE_ERROR');
	my @d = <F>;
	my @p;
	push(@p, OpenSRF::Utils::JSON->JSON2perl($_)) for @d;
	close(F);
	return \@p;
}

# collects the commands and sorts them on timestamp+delta
sub ol_collect_commands {
	my $ses = ol_find_session();
	my @commands;

	# cycle through every script loaded to this session
	for my $script ($ses->scripts) {
		my $coms = ol_file_to_perl($script->logfile);

		# cycle through all of the commands for this script
		for my $com (@$coms) {
			$$com{_workstation} = $script->workstation;
			$$com{_realtime} = $script->time_delta + $com->{timestamp};
			push( @commands, $com );
		}
	}

	# make sure thera are no blank commands
	@commands = grep { ($_ and $_->{type}) } @commands;

	# sort on realtime
	@commands = sort { $a->{_realtime} <=> $b->{_realtime} } @commands;

	# push user registrations to the front
	my @regs		= grep { $_->{type} eq 'register' } @commands;
	my @others	= grep { $_->{type} ne 'register' } @commands;

	return [ @regs, @others ];
}

sub ol_date {
	my $time = shift || CORE::time;
	my (undef,undef, undef, $mday,$mon,$year) = localtime($time);
	$mon++; $year	+= 1900;
	$mday	= "0$mday" unless $mday =~ /\d{2}/o;
	$mon	= "0$mon" unless $mon	=~ /\d{2}/o;
	return ($year, $mon, $mday);
}


# --------------------------------------------------------------------
# Moves all files from the pending directory to the archive directory
# and removes the pending directory
# --------------------------------------------------------------------
sub ol_archive_files {
	my $session = shift;
	my ($y, $m, $d) = ol_date();

	my $dir = "$basedir/pending/$org/$seskey";
	my $archdir = "$basedir/archive/$org/$seskey";
	$logger->debug("offline: archiving files to $archdir");

	# Tell the db the files are moving
	$_->logfile($archdir.'/'.$_->workstation.'.log') for ($session->scripts);

	qx/mkdir -p $archdir/;
	qx/mv $_ $archdir/ for <$dir/*>;
	qx/rmdir $dir/;
}


# --------------------------------------------------------------------
# Appends results to the results file.
# --------------------------------------------------------------------
my $rhandle;
sub ol_append_result {

	my $obj	= shift;
	my $last = shift;

	$obj = OpenSRF::Utils::JSON->perl2JSON($obj);

	if(!$rhandle) {
		open($rhandle, ">>$basedir/pending/$org/$seskey/results") 
			or ol_handle_event('OFFLINE_FILE_ERROR');
	}

	print $rhandle "$obj\n";
	close($rhandle) if $last;
}



# --------------------------------------------------------------------
# Runs the commands and returns the list of errors
# --------------------------------------------------------------------
sub ol_process_commands {

	my $session	 = shift;
	my $commands = shift;
	my $x        = 0;

	$session->start_time(CORE::time);

	for my $d ( @$commands ) {

		my $t		= $d->{type};
		my $last = ($x++ == scalar(@$commands) - 1) ? 1 : 0;
		my $res	= { command => $d };
		my $err;

		while( 1 ) {

			$err = undef;
			$logger->debug("offline: top of execute loop : $t");

			try {
				$res->{event} = ol_handle_checkin($d)	if $t eq 'checkin';
				$res->{event} = ol_handle_inhouse($d)	if $t eq 'in_house_use';
				$res->{event} = ol_handle_checkout($d) if $t eq 'checkout';
				$res->{event} = ol_handle_renew($d)		if $t eq 'renew';
				$res->{event} = ol_handle_register($d) if $t eq 'register';
	
			} catch Error with { $err = shift; };

			if( $err ) {

				if( ref($err) eq 'OpenSRF::EX::JabberDisconnected' ) {
					$logger->error("offline: we lost jabber .. trying to reconnect");
					ol_connect();

				} else {
					$res->{event} = OpenILS::Event->new('INTERNAL_SERVER_ERROR', debug => "$err");
					last;
				}

			} else { last; }

			sleep(1);
		}

		ol_append_result($res, $last);
		$session->num_complete( $session->num_complete + 1 );

		$logger->debug("offline: set session [".$session->key."] num_complete to ".$session->num_complete);
	}

	$session->end_time(CORE::time);
	$session->in_process(0);
}


# --------------------------------------------------------------------
# Runs an in_house_use action
# --------------------------------------------------------------------
sub ol_handle_inhouse {

	my $command		= shift;
	my $realtime	= $command->{_realtime};
	my $ws			= $command->{_workstation};
	my $barcode		= $command->{barcode};
	my $count		= $command->{count} || 1;
	my $use_time	= $command->{use_time} || "";

	$logger->activity("offline: in_house_use : requestor=". $requestor->id.", realtime=$realtime, ".  
		"workstation=$ws, barcode=$barcode, count=$count, use_time=$use_time");

	if( $count > 99 ) {
		return OpenILS::Event->new(
			'INTERNAL_SERVER_ERROR', payload => 'TOO MANY IN HOUSE USE');
	}

	my $ids = $U->simplereq(
		'open-ils.circ', 
		'open-ils.circ.in_house_use.create', $authtoken, 
		{ barcode => $barcode, count => $count, location => $org, use_time => $use_time } );
	
	return OpenILS::Event->new('SUCCESS', payload => $ids) if( ref($ids) eq 'ARRAY' );
	return $ids;
}



# --------------------------------------------------------------------
# Pulls the relevant circ args from the command, fetches data where 
# necessary
# --------------------------------------------------------------------
my %user_id_cache;
sub ol_circ_args_from_command {
	my $command = shift;

	my $type			= $command->{type};
	my $realtime	= $command->{_realtime};
	my $ws			= $command->{_workstation};
	my $barcode		= $command->{barcode} || "";
	my $cotime		= $command->{checkout_time} || "";
	my $pbc			= $command->{patron_barcode};
	my $due_date	= $command->{due_date} || "";
	my $noncat		= ($command->{noncat}) ? "yes" : "no"; # for logging

	$logger->activity("offline: $type : requestor=". $requestor->id.
		", realtime=$realtime, workstation=$ws, checkout_time=$cotime, ".
		"patron=$pbc, due_date=$due_date, noncat=$noncat");


	my $args = { 
		permit_override	=> 1, 
		barcode         => $barcode,		
		checkout_time   => $cotime, 
		patron_barcode  => $pbc,
		due_date        => $due_date 
    };

    if(ol_get_org_setting('circ.offline.username_allowed')) {

        my $format = ol_get_org_setting('opac.barcode_regex');
        if($format) {

            $format =~ s/^\/|\/$//g; # remove any couching //'s
            if($pbc !~ qr/$format/) {

                # the patron barcode does not match the configured barcode format
                # assume they passed a username instead

                my $user_id = $user_id_cache{$pbc} ||
                    $U->simplereq(
                        'open-ils.actor', 
                        'open-ils.actor.username.exists', 
                        $authtoken, $pbc);

                
                if($user_id) {
                    # a valid username was provided, update the args and cache
                    $user_id_cache{$pbc} = $user_id;
                    $args->{patron_id} = $user_id;
                    delete $args->{patron_barcode};
                }
            }
        }
    }


	if( $command->{noncat} ) {
		$args->{noncat} = 1;
		$args->{noncat_type} = $command->{noncat_type};
		$args->{noncat_count} = $command->{noncat_count};
	}

	return $args;
}

sub ol_get_org_setting {
    my $name = shift;
    return $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.ou_setting.ancestor_default',
        $org, $name, $authtoken);
}



# --------------------------------------------------------------------
# Performs a checkout action
# --------------------------------------------------------------------
sub ol_handle_checkout {
	my $command	= shift;
	my $args = ol_circ_args_from_command($command);

	if( $args->{noncat} and $args->{noncat_count} > 99 ) {
		return OpenILS::Event->new(
			'INTERNAL_SERVER_ERROR', payload => 'TOO MANY NON CATS');
	}

    if( $args->{barcode} ) {

        # $c becomes the Copy
        # $e possibily becomes the Exception
        my( $c, $e ) = $U->fetch_copy_by_barcode($args->{barcode});
        return $e if $e;

        my $barcode = $args->{barcode};
        # Have to have this config option (or org setting) and a
        # status_changed_time for skippage, and barcode not seen before
        if ((
                ol_get_org_setting(
                    'circ.offline.skip_checkout_if_newer_status_changed_time'
                )
                || $config{skip_late}
            )
            && length($c->status_changed_time())
            && ! $seen_barcode{$barcode}
        ) {
            $seen_barcode{$barcode} = 1;
            my $cts = DateTime::Format::ISO8601->parse_datetime( clean_ISO8601($c->status_changed_time()) )->epoch();
            my $xts = $command->{timestamp}; # Transaction Time Stamp
            $logger->activity("offline: ol_handle_checkout: considering status_changed_time for barcode=$barcode, cts=$cts, xts=$xts");

            # Asset has changed after this transaction, ignore
            if ($cts >= $xts) {
                $skip_barcode_for_status_changed{$barcode} = 1;
            }
        } else {
            $logger->activity("No skip check: barcode=$barcode seen_barcode=".$seen_barcode{$1}." status_changed_time=".$c->status_changed_time." ou_setting=".ol_get_org_setting('circ.offline.skip_checkout_if_newer_status_changed_time'));
        }
        if ($skip_barcode_for_status_changed{$barcode}) {
            $logger->activity("offline: ol_handle_checkout: barcode=$barcode has SKIP_ASSET_CHANGED");
            return OpenILS::Event->new(
                'SKIP_ASSET_CHANGED'
            );
        }
    }

    my $evt = $U->simplereq(
		'open-ils.circ', 'open-ils.circ.checkout', $authtoken, $args );

    # if the item is already checked out to this user and we are past 
    # the configured auto-renewal interval, try to renew the circ.
    if( ref $evt ne 'ARRAY' and
        $evt->{textcode} == 'OPEN_CIRCULATION_EXISTS' and 
        $evt->{payload}->{auto_renew}) {

            return ol_handle_renew($command);
    }

    return $evt;
}


# --------------------------------------------------------------------
# Performs the renewal action
# --------------------------------------------------------------------
sub ol_handle_renew {
	my $command = shift;
	my $args = ol_circ_args_from_command($command);
	my $t = time;

    if( $args->{barcode} ) {

        # $c becomes the Copy
        # $e possibily becomes the Exception
        my( $c, $e ) = $U->fetch_copy_by_barcode($args->{barcode});
        return $e if $e;

        my $barcode = $args->{barcode};
        # Have to have this config option (or org setting) and a
        # status_changed_time for skippage, and barcode not seen before
        if ((
                ol_get_org_setting(
                    'circ.offline.skip_renew_if_newer_status_changed_time'
                )
                || $config{skip_late}
            )
            && length($c->status_changed_time())
            && ! $seen_barcode{$barcode}
        ) {
            $seen_barcode{$barcode} = 1;
            my $cts = DateTime::Format::ISO8601->parse_datetime( clean_ISO8601($c->status_changed_time()) )->epoch();
            my $xts = $command->{timestamp}; # Transaction Time Stamp
            $logger->activity("offline: ol_handle_renew: considering status_changed_time for barcode=$barcode, cts=$cts, xts=$xts");

            # Asset has changed after this transaction, ignore
            if ($cts >= $xts) {
                $skip_barcode_for_status_changed{$barcode} = 1;
            }
        } else {
            $logger->activity("No skip check: barcode=$barcode seen_barcode=".$seen_barcode{$1}." status_changed_time=".$c->status_changed_time." ou_setting=".ol_get_org_setting('circ.offline.skip_renew_if_newer_status_changed_time'));
        }
        if ($skip_barcode_for_status_changed{$barcode}) {
            $logger->activity("offline: ol_handle_renew: barcode=$barcode has SKIP_ASSET_CHANGED");
            return OpenILS::Event->new(
                'SKIP_ASSET_CHANGED'
            );
        }
    }

	return $U->simplereq(
		'open-ils.circ', 'open-ils.circ.renew.override', $authtoken, $args );
}


# --------------------------------------------------------------------
# Runs a checkin action
# --------------------------------------------------------------------
sub ol_handle_checkin {

	my $command		= shift;
	my $realtime	= $command->{_realtime};
	my $ws			= $command->{_workstation};
	my $barcode		= $command->{barcode};
	my $backdate	= $command->{backdate} || "";

	$logger->activity("offline: checkin : requestor=". $requestor->id.
		", realtime=$realtime, ".  "workstation=$ws, barcode=$barcode, backdate=$backdate");

    if( $barcode ) {

        # $c becomes the Copy
        # $e possibily becomes the Exception
        my( $c, $e ) = $U->fetch_copy_by_barcode($barcode);
        return $e if $e;

        # Have to have this config option (or org setting) and a
        # status_changed_time for skippage, and barcode not seen before
        if ((
                ol_get_org_setting(
                    'circ.offline.skip_checkin_if_newer_status_changed_time'
                )
                || $config{skip_late}
            )
            && length($c->status_changed_time())
            && ! $seen_barcode{$barcode}
        ) {
            $seen_barcode{$barcode} = 1;
            my $cts = DateTime::Format::ISO8601->parse_datetime( clean_ISO8601($c->status_changed_time()) )->epoch();
            my $xts = $command->{timestamp}; # Transaction Time Stamp
            $logger->activity("offline: ol_handle_checkin: considering status_changed_time for barcode=$barcode, cts=$cts, xts=$xts");

            # Asset has changed after this transaction, ignore
            if ($cts >= $xts) {
                $skip_barcode_for_status_changed{$barcode} = 1;
            }
        } else {
            $logger->activity("No skip check: barcode=$barcode seen_barcode=".$seen_barcode{$1}." status_changed_time=".$c->status_changed_time." ou_setting=".ol_get_org_setting('circ.offline.skip_checkin_if_newer_status_changed_time'));
        }
        if ($skip_barcode_for_status_changed{$barcode}) {
            $logger->activity("offline: ol_handle_checkin: barcode=$barcode has SKIP_ASSET_CHANGED");
            return OpenILS::Event->new(
                'SKIP_ASSET_CHANGED'
            );
        }
    }

	return $U->simplereq(
		'open-ils.circ', 
		'open-ils.circ.checkin', $authtoken,
		{ barcode => $barcode, backdate => $backdate } );
}



# --------------------------------------------------------------------
# Registers a new patron
# --------------------------------------------------------------------
sub ol_handle_register {
	my $command = shift;

	my $barcode = $command->{user}->{card}->{barcode};
	delete $command->{user}->{card}; 
	delete $command->{user}->{cards} if $command->{user}->{cards}; 

	$logger->info("offline: creating new user with barcode $barcode");

	# now, create the user
	my $actor	= Fieldmapper::actor::user->new;
	my $card		= Fieldmapper::actor::card->new;


	# username defaults to the barcode
	$actor->usrname( ($actor->usrname) ? $actor->usrname : $barcode );

	# Set up all of the virtual IDs, isnew, etc.
	$actor->isnew(1);
	$actor->id(-1);
	$actor->card(-1);
	$actor->cards([$card]);

	$card->isnew(1);
	$card->id(-1);
	$card->usr(-1);
	$card->barcode($barcode);

	my $billing_address;
	my $mailing_address;

	my @sresp;
	for my $resp (@{$command->{user}->{survey_responses}}) {
		my $sr = Fieldmapper::action::survey_response->new;
		$sr->$_( $resp->{$_} ) for keys %$resp;
		$sr->isnew(1);
		$sr->usr(-1);
		push(@sresp, $sr);
		$logger->debug("offline: created new survey response for survey ".$sr->survey);
	}
	delete $command->{user}->{survey_responses};
	$actor->survey_responses(\@sresp) if @sresp;

    my $bid = undef;
	# extract the billing address
	if( my $addr = $command->{user}->{billing_address} ) {
        $bid = $command->{user}->{billing_address}->{id};
		$billing_address = Fieldmapper::actor::user_address->new;
		$billing_address->$_($addr->{$_}) for keys %$addr;
		$billing_address->isnew(1);
		$billing_address->id(-1);
		$billing_address->usr(-1);
		delete $command->{user}->{billing_address};
		$logger->debug("offline: read billing address ".$billing_address->street1);
	}

    my $mid = undef;
	# extract the mailing address
	if( my $addr = $command->{user}->{mailing_address} ) {
        $mid = $command->{user}->{mailing_address}->{id};
        if ($webclient && $mid != $bid) {
		    $mailing_address = Fieldmapper::actor::user_address->new;
		    $mailing_address->$_($addr->{$_}) for keys %$addr;
		    $mailing_address->isnew(1);
		    $mailing_address->id(-2);
		    $mailing_address->usr(-1);
		    $logger->debug("offline: read mailing address ".$mailing_address->street1);
        } elsif (!$webclient) {
		    $mailing_address = Fieldmapper::actor::user_address->new;
		    $mailing_address->$_($addr->{$_}) for keys %$addr;
		    $mailing_address->isnew(1);
		    $mailing_address->id(-2);
		    $mailing_address->usr(-1);
		    $logger->debug("offline: read mailing address ".$mailing_address->street1);
        }
		delete $command->{user}->{mailing_address};
	}

	# make sure we have values for both
	$billing_address ||= $mailing_address;
	$mailing_address ||= $billing_address;

	$actor->billing_address($billing_address->id);
	$actor->mailing_address($mailing_address->id);
	$actor->addresses([$mailing_address]);

	push( @{$actor->addresses}, $billing_address ) 
		unless $billing_address->id eq $mailing_address->id;

    my $aid = -3;
    for my $a ( @{$command->{user}->{addresses}} ) {
        next if ($a->{id} == $bid || $a->{id} == $mid);
    	# extract all other addresses
        my $addr = Fieldmapper::actor::user_address->new;
	    $addr->$_($a->{$_}) for keys %$a;
		$addr->isnew(1);
    	$addr->id($aid);
	    $addr->usr(-1);
    	$logger->debug("offline: read other address ".$addr->street1);
        $aid--;
        push( @{$actor->addresses}, $addr );
    }
	
	# pull all of the rest of the data from the command blob
	$actor->$_( $command->{user}->{$_} ) for grep { $_ ne 'addresses' } keys %{$command->{user}};

    # calculate the expire date for the patron based on the profile group
    my ($grp) = grep {$_->id == $actor->profile} @$user_groups;
    if($grp) {
        my $seconds = OpenILS::Utils::DateTime->interval_to_seconds($grp->perm_interval);
        my $expire_date = DateTime->from_epoch(epoch => DateTime->now->epoch + $seconds)->epoch;
		$logger->debug("offline: setting expire date to $expire_date");
        $actor->expire_date($U->epoch2ISO8601($expire_date));
    }

	$logger->debug("offline: creating user object...");
	$actor = $U->simplereq(
		'open-ils.actor', 
		'open-ils.actor.patron.update', $authtoken, $actor);

	return $actor if(ref($actor) eq 'HASH'); # an event occurred

	return OpenILS::Event->new('SUCCESS', payload => $actor);
}







