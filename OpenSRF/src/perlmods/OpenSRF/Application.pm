package OpenSRF::Application;
use vars qw/$_app $log @_METHODS $thunk $server_class/;

use base qw/OpenSRF/;
use OpenSRF::AppSession;
use OpenSRF::DomainObject::oilsMethod;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::Utils::Logger qw/:level/;
use Data::Dumper;
use Time::HiRes qw/time/;
use OpenSRF::EX qw/:try/;
#use OpenSRF::UnixServer;  # to get the server class from UnixServer::App

sub DESTROY{};

use strict;
use warnings;

$log = 'OpenSRF::Utils::Logger';

our $in_request = 0;
our @pending_requests;

sub api_name {
	my $self = shift;
	return $self->{api_name};
}

sub server_class {
	my $class = shift;
	if($class) {
		$server_class = $class;
	}
	return $server_class;
}

sub thunk {
	my $self = shift;
	my $flag = shift;
	$thunk = $flag if (defined $flag);
	return $thunk;
}

sub application_implementation {
	my $self = shift;
	my $app = shift;

	if (defined $app) {
		$_app = $app;
		eval "use $_app;";
		if( $@ ) {
			$log->error( "Error loading application_implementation: $app -> $@", ERROR);
		}

	}

	return $_app;
}

sub handler {
	my ($self, $session, $app_msg) = @_;

	if( ! $app_msg ) {
		return 0;  # error?
	}

	$log->debug( "In Application::handler()", DEBUG );

	my $app = $self->application_implementation;

	if( $app ) {
		$log->debug( "Application is $app", DEBUG);
	}
	$log->debug( "Message is ".$app_msg->toString(1), INTERNAL);


	if ($session->last_message_type eq 'REQUEST') {
		$log->debug( "We got a REQUEST: ". $app_msg->method, INFO );

		my $method_name = $app_msg->method;
		$log->debug( " * Looking up $method_name inside $app", DEBUG);

		my $method_proto = $session->last_message_api_level;
		$log->debug( " * Method API Level [$method_proto]", DEBUG);

		my $coderef = $app->method_lookup( $method_name, $method_proto, 1, 1 );

		unless ($coderef) {
			$session->status( OpenSRF::DomainObject::oilsMethodException->new() );
			return 1;
		}

		$log->debug( " (we got coderef $coderef", DEBUG);

		unless ($session->continue_request) {
			$session->status(
				OpenSRF::DomainObject::oilsConnectStatus->new(
						statusCode => STATUS_REDIRECTED(),
						status => 'Disconnect on max requests' ) );
			$session->kill_me;
			return 1;
		}

		if (ref $coderef) {
			my @args = $app_msg->params;
			my $appreq = OpenSRF::AppRequest->new( $session );

			$log->debug( "in_request = $in_request : [" . $appreq->threadTrace."]", DEBUG );
			if( $in_request ) {
				$log->debug( "Pushing onto pending requests: " . $appreq->threadTrace, DEBUG );
				push @pending_requests, [ $appreq, \@args, $coderef ]; 
				return 1;
			}


			$in_request++;

			$log->debug( "Executing coderef for {$method_name -> ".join(', ', @args)."}", INTERNAL );

			my $resp;
			try {
				my $start = time();
				$resp = $coderef->run( $appreq, @args); 
				my $time = sprintf '%.3f', time() - $start;
				$log->debug( "Method duration for {$method_name -> ".join(', ', @args)."}:  ". $time, DEBUG );
				if( defined( $resp ) ) {
					#$log->debug( "Calling respond_complete: ". $resp->toString(), INTERNAL );
					$appreq->respond_complete( $resp );
				} else {
				        $appreq->status( OpenSRF::DomainObject::oilsConnectStatus->new(
								statusCode => STATUS_COMPLETE(),
								status => 'Request Complete' ) );
				}
			} catch Error with {
				my $e = shift;
				$e = $e->{-text} || $e->message if (ref $e);
				my $sess_id = $session->session_id;
				$session->status(
					OpenSRF::DomainObject::oilsMethodException->new(
							statusCode	=> STATUS_INTERNALSERVERERROR(),
							status		=> " *** Call to [$method_name] failed for session ".
									   "[$sess_id], thread trace [".$appreq->threadTrace."]:\n".$e
					)
				);
			};



			# ----------------------------------------------


			# XXX may need this later
			# $_->[1] = 1 for (@OpenSRF::AppSession::_CLIENT_CACHE);

			$in_request--;

			$log->debug( "Pending Requests: " . scalar(@pending_requests), INTERNAL );

			# cycle through queued requests
			while( my $aref = shift @pending_requests ) {
				$in_request++;
				my $resp;
				try {
					my $start = time;
					my $response = $aref->[2]->run( $aref->[0], @{$aref->[1]} );
					my $time = sprintf '%.3f', time - $start;
					$log->debug( "Method duration for {[".$aref->[2]->name." -> ".join(', ',@{$aref->[1]}).'}:  '.$time, DEBUG );

					$appreq = $aref->[0];	
					if( ref( $response ) ) {
						$log->debug( "Calling respond_complete: ". $response->toString(), INTERNAL );
						$appreq->respond_complete( $response );
					} else {
					        $appreq->status( OpenSRF::DomainObject::oilsConnectStatus->new(
									statusCode => STATUS_COMPLETE(),
									status => 'Request Complete' ) );
					}
					$log->debug( "Executed: " . $appreq->threadTrace, DEBUG );
				} catch Error with {
					my $e = shift;
					$session->status(
						OpenSRF::DomainObject::oilsMethodException->new(
								statusCode => STATUS_INTERNALSERVERERROR(),
								status => "Call to [".$aref->[2]->name."] faild:  ".$e->{-text}
						)
					);
				};
				$in_request--;
			}

			return 1;
		} 
		my $res = OpenSRF::DomainObject::oilsMethodException->new;
		$session->send('ERROR', $res);
		$session->kill_me;
		return 1;

	} else {
		$log->debug( "Pushing ". $app_msg->toString ." onto queue", INTERNAL );
		$session->push_queue([ $app_msg, $session->last_threadTrace ]);
	}

	$session->last_message_type('');
	$session->last_message_api_level('');

	return 1;
}

sub register_method {
	my $self = shift;
	my $app = ref($self) || $self;
	my %args = @_;


	throw OpenSRF::DomainObject::oilsMethodException unless ($args{method});

	$args{api_level} ||= 1;
	$args{stream} ||= 0;
	$args{remote} ||= 0;
	$args{package} = $app;                
	$args{server_class} = server_class();
	$args{api_name} ||= $args{server_class} . '.' . $args{method};

	$_METHODS[$args{api_level}]{$args{api_name}} = bless \%args => $app;

	__PACKAGE__->register_method(
		stream => 0,
		api_name => $args{api_name}.'.atomic',
		method => 'make_stream_atomic'
	) if ($args{stream});
}

sub retrieve_remote_apis {
	my $session = OpenSRF::AppSession->create('router');
	try {
		$session->connect or OpenSRF::EX::WARN->throw("Connection to router timed out");
	} catch Error with {
		my $e = shift;
		$log->debug( "Remote subrequest returned an error:\n". $e );
		return undef;
	} finally {
		return undef unless ($session->state == $session->CONNECTED);
	};

	my $req = $session->request( 'opensrf.router.info.class.list' );
	my $list = $req->recv;

	if( UNIVERSAL::isa($list,"Error") ) {
		throw $list;
	}

	my $content = $list->content;

	$req->finish;
	$session->finish;
	$session->disconnect;

	my %u_list = map { ($_ => 1) } @$content;

	for my $class ( keys %u_list ) {
		next if($class eq $server_class);
		populate_remote_method_cache($class);
	}
}

sub populate_remote_method_cache {
	my $class = shift;

	my $session = OpenSRF::AppSession->create($class);
	try {
		$session->connect or OpenSRF::EX::WARN->throw("Connection to $class timed out");

		my $req = $session->request( 'opensrf.system.method.all' );

		while (my $method = $req->recv) {
			next if (UNIVERSAL::isa($method, 'Error'));

			$method = $method->content;
			next if ( exists($_METHODS[$$method{api_level}]) &&
				exists($_METHODS[$$method{api_level}]{$$method{api_name}}) );
			$method->{remote} = 1;
			bless($method, __PACKAGE__ );
			$_METHODS[$$method{api_level}]{$$method{api_name}} = $method;
		}

		$req->finish;
		$session->finish;
		$session->disconnect;

	} catch Error with {
		my $e = shift;
		$log->debug( "Remote subrequest returned an error:\n". $e );
		return undef;
	};
}

sub method_lookup {             
	my $self = shift;
	my $method = shift;
	my $proto = shift;
	my $no_recurse = shift || 0;
	my $no_remote = shift || 0;

	# this instead of " || 1;" above to allow api_level 0
	$proto = 1 unless (defined $proto);

	my $class = ref($self) || $self;

	$log->debug("Lookup of [$method] by [$class]", DEBUG);
	$log->debug("Available methods\n".Dumper(\@_METHODS), INTERNAL);

	my $meth;
	if (__PACKAGE__->thunk) {
		for my $p ( reverse(1 .. $proto) ) {
			if (exists $_METHODS[$p]{$method}) {
				$meth = $_METHODS[$p]{$method};
			}
		}
	} else {
		if (exists $_METHODS[$proto]{$method}) {
			$meth = $_METHODS[$proto]{$method};
		}
	}

	if (defined $meth) {
		$log->debug("Looks like we found [$method]!", DEBUG);
		$log->debug("Method object is ".Dumper($meth), INTERNAL);
		if($no_remote and $meth->{remote}) {
			$log->debug("OH CRAP We're not supposed to return remote methods", WARN);
			return undef;
		}

	} elsif (!$no_recurse) {
		retrieve_remote_apis();
		$meth = $self->method_lookup($method,$proto,1);
	}

	return $meth;
}

sub run {
	my $self = shift;
	my $req = shift;

	my $resp;
	my @params = @_;

	if ( !UNIVERSAL::isa($req, 'OpenSRF::AppRequest') ) {
		$log->debug("Creating a SubRequest object", DEBUG);
		unshift @params, $req;
		$req = OpenSRF::AppSubrequest->new;
	} else {
		$log->debug("This is a top level request", DEBUG);
	}

	if (!$self->{remote}) {
		my $code ||= \&{$self->{package} . '::' . $self->{method}};
		$resp = $code->($self, $req, @params);

		if ( ref($req) and UNIVERSAL::isa($req, 'OpenSRF::AppSubrequest') ) {
			$req->respond($resp) if (defined $resp);
			$log->debug("A SubRequest object is responding " . join(" ",$req->responses), DEBUG);
			return $req->responses;
		} else {
			$log->debug("A top level Request object is responding $resp", DEBUG);
			return $resp;
		}
	} else {
		my $session = OpenSRF::AppSession->create($self->{server_class});
		try {
			$session->connect or OpenSRF::EX::WARN->throw("Connection to [$$self{server_class}] timed out");
			my $remote_req = $session->request( $self->{api_name}, @params );
			while (my $remote_resp = $remote_req->recv) {
				OpenSRF::Utils::Logger->debug("Remote Subrequest Received " . $remote_resp, INTERNAL );
				if( UNIVERSAL::isa($remote_resp,"Error") ) {
					throw $remote_resp;
				}
				$req->respond( $remote_resp->content );
			}
			$remote_req->finish();
			$session->finish();

		} catch Error with {
			my $e = shift;
			$log->debug( "Remote subrequest returned an error:\n". $e );
			return undef;
		};

		$log->debug( "Remote Subrequest Responses " . join(" ", $req->responses), INTERNAL );

		return $req->responses;
	}
	# huh? how'd we get here...
	return undef;
}

sub introspect {
	my $self = shift;
	my $client = shift;
	my $method = shift;

	$method = undef if ($self->{api_name} =~ /all$/o);

	for my $api_level ( 1 .. $#_METHODS ) {
		for my $api_name ( sort keys %{$_METHODS[$api_level]} ) {
			if (!$_METHODS[$api_level]{$api_name}{remote}) {
				if (defined($method)) {
					if ($api_name =~ /$method/) {
						$client->respond( $_METHODS[$api_level]{$api_name} );
					}
				} else {
					$client->respond( $_METHODS[$api_level]{$api_name} );
				}
			}
		}
	}

	return undef;
}
__PACKAGE__->register_method(
	stream => 1,
	method => 'introspect',
	api_name => 'opensrf.system.method.all'
);

__PACKAGE__->register_method(
	stream => 1,
	method => 'introspect',
	argc => 1,
	api_name => 'opensrf.system.method'
);

sub make_stream_atomic {
	my $self = shift;
	my $req = shift;
	my @args = @_;

	(my $m_name = $self->api_name) =~ s/\.atomic$//o;
	my @results = $self->method_lookup($m_name)->run(@args);

	if (@results == 1) {
		return $results[0];
	}
	return \@results;
}


1;
