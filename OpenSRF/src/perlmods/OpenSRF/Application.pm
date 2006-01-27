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
use Carp;
#use OpenSRF::UnixServer;  # to get the server class from UnixServer::App

sub DESTROY{};

use strict;
use warnings;

$log = 'OpenSRF::Utils::Logger';

our $in_request = 0;
our @pending_requests;

sub package {
	my $self = shift;
	return 1 unless ref($self);
	return $self->{package};
}

sub signature {
	my $self = shift;
	return 0 unless ref($self);
	return $self->{signature};
}

sub argc {
	my $self = shift;
	return 0 unless ref($self);
	return $self->{argc};
}

sub api_name {
	my $self = shift;
	return 1 unless ref($self);
	return $self->{api_name};
}

sub api_level {
	my $self = shift;
	return 1 unless ref($self);
	return $self->{api_level};
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
		return 1;  # error?
	}

	$log->debug( "In Application::handler()", DEBUG );

	my $app = $self->application_implementation;

	if( $app ) {
		$log->debug( "Application is $app", DEBUG);
	}

	if ($session->last_message_type eq 'REQUEST') {
		$log->debug( "We got a REQUEST: ". $app_msg->method);

		my $method_name = $app_msg->method;
		$log->debug( " * Looking up $method_name inside $app", DEBUG);

		my $method_proto = $session->last_message_api_level;
		$log->debug( " * Method API Level [$method_proto]", DEBUG);

		my $coderef = $app->method_lookup( $method_name, $method_proto, 1, 1 );

		unless ($coderef) {
			$session->status( OpenSRF::DomainObject::oilsMethodException->new( 
						statusCode => STATUS_NOTFOUND(),
						status => "Method [$method_name] not found for $app"));
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

			$log->debug( "Executing coderef for {$method_name}", INTERNAL );

			my $resp;
			try {
				# un-if(0) this block to enable param checking based on signature and argc
				if (0) {
					if (@args < $coderef->argc) {
						die	"Not enough params passed to ".
							$coderef->api_name." : requires ". $coderef->argc
					}
					if (@args) {
						my $sig = $coderef->signature;
						if ($sig && exists $sig->{params}) {
							for my $p (0 .. scalar(@{ $sig->{params} }) - 1 ) {
								my $s = $sig->{params}->[$p];
								my $a = $args[$p];
								if ($s->{class} && JSON->lookup_hint(ref $a) ne $s->{class}) {
									die "Incorrect param class at position $p : should be a '$$s{class}'";
								} elsif ($s->{type}) {
									if (lc($s->{type}) eq 'object' && $a !~ /HASH/o) {
										die "Incorrect param type at position $p : should be an 'object'";
									} elsif (lc($s->{type}) eq 'array' && $a !~ /ARRAY/o) {
										die "Incorrect param type at position $p : should be an 'array'";
									} elsif (lc($s->{type}) eq 'number' && (ref($a) || $a !~ /^-?\d+(?:\.\d+)?$/o)) {
										die "Incorrect param type at position $p : should be a 'number'";
									} elsif (lc($s->{type}) eq 'string' && ref($a)) {
										die "Incorrect param type at position $p : should be a 'string'";
									}
								}
							}
						}
					}
				}

				my $start = time();
				warn "About to run...\n";
				$resp = $coderef->run( $appreq, @args); 
				warn "Done running...\n";
				my $time = sprintf '%.3f', time() - $start;

				$log->debug( "Method duration for {$method_name}:  ". $time, INFO );
				if( defined( $resp ) ) {
					$appreq->respond_complete( $resp );
				} else {
				        $appreq->status( OpenSRF::DomainObject::oilsConnectStatus->new(
								statusCode => STATUS_COMPLETE(),
								status => 'Request Complete' ) );
				}
			} catch Error with {
				my $e = shift;
				warn "Caught error from 'run' method: $e\n";

				if(UNIVERSAL::isa($e,"Error")) {
					$e = $e->stringify();
				} 
				my $sess_id = $session->session_id;
				$session->status(
					OpenSRF::DomainObject::oilsMethodException->new(
							statusCode	=> STATUS_INTERNALSERVERERROR(),
							status		=> " *** Call to [$method_name] failed for session ".
									   "[$sess_id], thread trace ".
									   "[".$appreq->threadTrace."]:\n$e\n"
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
					# un-if(0) this block to enable param checking based on signature and argc
					if (0) {
						if (@args < $aref->[2]->argc) {
							die	"Not enough params passed to ".
								$aref->[2]->api_name." : requires ". $aref->[2]->argc
						}
						if (@args) {
							my $sig = $aref->[2]->signature;
							if ($sig && exists $sig->{params}) {
								for my $p (0 .. scalar(@{ $sig->{params} }) - 1 ) {
									my $s = $sig->{params}->[$p];
									my $a = $args[$p];
									if ($s->{class} && JSON->lookup_hint(ref $a) ne $s->{class}) {
										die "Incorrect param class at position $p : should be a '$$s{class}'";
									} elsif ($s->{type}) {
										if (lc($s->{type}) eq 'object' && $a !~ /HASH/o) {
											die "Incorrect param type at position $p : should be an 'object'";
										} elsif (lc($s->{type}) eq 'array' && $a !~ /ARRAY/o) {
											die "Incorrect param type at position $p : should be an 'array'";
										} elsif (lc($s->{type}) eq 'number' && (ref($a) || $a !~ /^-?\d+(?:\.\d+)?$/o)) {
											die "Incorrect param type at position $p : should be a 'number'";
										} elsif (lc($s->{type}) eq 'string' && ref($a)) {
											die "Incorrect param type at position $p : should be a 'string'";
										}
									}
								}
							}
						}
					}

					my $start = time;
					my $response = $aref->[2]->run( $aref->[0], @{$aref->[1]} );
					my $time = sprintf '%.3f', time - $start;
					$log->debug( "Method duration for {[".$aref->[2]->api_name." -> ".join(', ',@{$aref->[1]}).'}:  '.$time, DEBUG );

					$appreq = $aref->[0];	
					if( ref( $response ) ) {
						$appreq->respond_complete( $response );
					} else {
					        $appreq->status( OpenSRF::DomainObject::oilsConnectStatus->new(
									statusCode => STATUS_COMPLETE(),
									status => 'Request Complete' ) );
					}
					$log->debug( "Executed: " . $appreq->threadTrace, DEBUG );
				} catch Error with {
					my $e = shift;
					if(UNIVERSAL::isa($e,"Error")) {
						$e = $e->stringify();
					}
					$session->status(
						OpenSRF::DomainObject::oilsMethodException->new(
								statusCode => STATUS_INTERNALSERVERERROR(),
								status => "Call to [".$aref->[2]->api_name."] faild:  $e"
						)
					);
				};
				$in_request--;
			}

			return 1;
		} 

		my $res = OpenSRF::DomainObject::oilsMethodException->new( 
				status => "Received non-REQUEST message in Application handler");
		$session->send('ERROR', $res);
		$session->kill_me;
		return 1;

	} else {
		$session->push_queue([ $app_msg, $session->last_threadTrace ]);
	}

	$session->last_message_type('');
	$session->last_message_api_level('');

	return 1;
}

sub is_registered {
	my $self = shift;
	my $api_name = shift;
	my $api_level = shift || 1;
	return exists($_METHODS[$api_level]{$api_name});
}


sub normalize_whitespace {
	my $txt = shift;

	$txt =~ s/^\s+//gso;
	$txt =~ s/\s+$//gso;
	$txt =~ s/\s+/ /gso;
	$txt =~ s/\n//gso;
	$txt =~ s/\. /\.  /gso;

	return $txt;
}

sub parse_string_signature {
	my $string = shift;
	my @chunks = split(/\@/so, $string);

	my @params;
	my $ret;
	my $desc = '';
	for (@chunks) {
		if (/^return (.+)$/so) {
			$ret = [normalize_whitespace($1)];
		} elsif (/^param (\w+) \b(.+)$/so) {
			push @params, [ $1, normalize_whitespace($2) ];
		} else {
			$desc .= '@' if $desc;
			$desc .= $_;
		}
	}

	return [normalize_whitespace($desc),\@params, $ret];
}

sub parse_array_signature {
	my $array = shift;
	my ($d,$p,$r) = @$array;

	return {
		desc	=> $d,
		params	=> [
			map { 
				{ name  => $$_[0],
				  desc  => $$_[1],
				  type  => $$_[2],
				  class => $$_[3],
				}
			} @$p
		],
		'return'=>
			{ desc  => $$r[0],
			  type  => $$r[1],
			  class => $$r[2],
			}
	};
}

sub register_method {
	my $self = shift;
	my $app = ref($self) || $self;
	my %args = @_;


	throw OpenSRF::DomainObject::oilsMethodException unless ($args{method});

	$args{api_level} = 1 unless(defined($args{api_level}));
	$args{stream} ||= 0;
	$args{remote} ||= 0;
	$args{argc} ||= 0;
	$args{package} ||= $app;                
	$args{server_class} = server_class();
	$args{api_name} ||= $args{server_class} . '.' . $args{method};

	# un-if(0) this block to enable signature parsing
	if (!$args{signature}) {
		if ($args{notes} && !ref($args{notes})) {
			$args{signature} =
				parse_array_signature( parse_string_signature( $args{notes} ) );
		}
	} elsif( !ref($args{signature}) ) {
		$args{signature} =
			parse_array_signature( parse_string_signature( $args{notes} ) );
	} elsif( ref($args{signature}) eq 'ARRAY') {
		$args{signature} =
			parse_array_signature( $args{signature} );
	}
	
	unless ($args{object_hint}) {
		($args{object_hint} = $args{package}) =~ s/::/_/go;
	}

	JSON->register_class_hint( name => $args{package}, hint => $args{object_hint}, type => "hash" );

	$_METHODS[$args{api_level}]{$args{api_name}} = bless \%args => $app;

	__PACKAGE__->register_method(
		stream => 0,
		argc => $args{argc},
		api_name => $args{api_name}.'.atomic',
		method => 'make_stream_atomic',
		notes => "This is a system generated method.  Please see the definition for $args{api_name}",
	) if ($args{stream});
}

sub retrieve_remote_apis {
	my $method = shift;
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
		populate_remote_method_cache($class, $method);
	}
}

sub populate_remote_method_cache {
	my $class = shift;
	my $meth = shift;

	my $session = OpenSRF::AppSession->create($class);
	try {
		$session->connect or OpenSRF::EX::WARN->throw("Connection to $class timed out");

		my $call = 'opensrf.system.method.all' unless (defined $meth);
		$call = 'opensrf.system.method' if (defined $meth);

		my $req = $session->request( $call, $meth );

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
	$proto = $self->api_level unless (defined $proto);

	my $class = ref($self) || $self;

	$log->debug("Lookup of [$method] by [$class] in api_level [$proto]", DEBUG);
	$log->debug("Available methods\n\t".join("\n\t", keys %{ $_METHODS[$proto] }), INTERNAL);

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
		$log->debug("We didn't find [$method], asking everyone else.", DEBUG);
		retrieve_remote_apis($method);
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
		$log->debug("Created coderef [$code] for $$self{package}::$$self{method}",DEBUG);
		my $err = undef;

		try {
			$resp = $code->($self, $req, @params);

		} catch Error with {
			my $e = shift;
			$err = $e;
			warn "Method 'run' catching error: $e\n";

			if( ref($self) eq 'HASH') {
				$log->error("Sub $$self{package}::$$self{method} DIED!!!\n\t$e\n", ERROR);
			}
		};

		if($err) {
			if(UNIVERSAL::isa($err,"Error")) { 
				warn "Throwing from method run:\n$err\n------------------\n";
				throw $err;
			} else {
				die $err->stringify; 
			}
		}


		$log->debug("Coderef for [$$self{package}::$$self{method}] has been run", DEBUG);

		if ( ref($req) and UNIVERSAL::isa($req, 'OpenSRF::AppSubrequest') ) {
			$log->debug("A SubRequest object is responding", DEBUG);
			$req->respond($resp) if (defined $resp);
			$log->debug("... Responding with : " . join(" ",$req->responses), DEBUG);
			return $req->responses;
		} else {
			$log->debug("A top level Request object is responding $resp", DEBUG) if (defined $resp);
			return $resp;
		}
	} else {
		my $session = OpenSRF::AppSession->create($self->{server_class});
		try {
			#$session->connect or OpenSRF::EX::WARN->throw("Connection to [$$self{server_class}] timed out");
			my $remote_req = $session->request( $self->{api_name}, @params );
			while (my $remote_resp = $remote_req->recv) {
				OpenSRF::Utils::Logger->debug("Remote Subrequest Received " . $remote_resp, INTERNAL );
				if( UNIVERSAL::isa($remote_resp,"Error") ) {
					throw $remote_resp;
				}
				$req->respond( $remote_resp->content );
			}
			$remote_req->finish();

		} catch Error with {
			my $e = shift;
			$log->debug( "Remote subrequest returned an error:\n". $e );
			return undef;
		};

		if ($session) {
			$session->disconnect();
			$session->finish();
		}

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

	$method = undef if ($self->api_name =~ /all$/o);

	for my $api_level ( reverse(1 .. $#_METHODS) ) {
		for my $api_name ( sort keys %{$_METHODS[$api_level]} ) {
			if (!$_METHODS[$api_level]{$api_name}{remote}) {
				if (defined($method)) {
					if ($api_name =~ $method) {
						$client->respond( $_METHODS[$api_level]{$api_name} );
					}
				} else {
					$log->debug( "Returning definition for method [$api_name]", INTERNAL );
					$client->respond( $_METHODS[$api_level]{$api_name} );
					$log->debug( "responed with definition for method [$api_name]", INTERNAL );
				}
			}
		}
	}

	return undef;
}
__PACKAGE__->register_method(
	stream => 1,
	method => 'introspect',
	api_name => 'opensrf.system.method.all',
	argc => 0,
	signature => {
		desc => q/This method is used to introspect an entire OpenSRF Application/,
		return => {
			desc => q/A stream of objects describing the methods available via this OpenSRF Application/,
			type => 'object'
		}
	},
);
__PACKAGE__->register_method(
	stream => 1,
	method => 'introspect',
	argc => 1,
	api_name => 'opensrf.system.method',
	argc => 1,
	signature => {
		desc => q/Use this method to get the definition of a single OpenSRF Method/,
		params => [
			{ desc => q/The method to introspect/,
			  type => 'string' },
		],
		return => { desc => q/An object describing the method requested, or an error if it can't be found/,
			    type => 'object' }
	},
);

sub echo_method {
	my $self = shift;
	my $client = shift;
	my @args = @_;

	$client->respond( $_ ) for (@args);
	return undef;
}
__PACKAGE__->register_method(
	stream => 1,
	method => 'echo_method',
	argc => 1,
	api_name => 'opensrf.system.echo',
	signature => {
		desc => q/A test method that will echo back it's arguments in a streaming response/,
		params => [
			{ desc => q/One or more arguments to echo back/ }
		],
		return => { desc => q/A stream of the arguments passed/ }
	},
);

sub make_stream_atomic {
	my $self = shift;
	my $req = shift;
	my @args = @_;

	(my $m_name = $self->api_name) =~ s/\.atomic$//o;
	my @results = $self->method_lookup($m_name)->run(@args);

	return \@results;
}


1;


