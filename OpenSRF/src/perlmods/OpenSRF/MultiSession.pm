package OpenSRF::MultiSession;
use OpenSRF::AppSession;
use OpenSRF::Utils::Logger;
use Time::HiRes qw/time usleep/;

my $log = 'OpenSRF::Utils::Logger';

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my $self = bless {@_} => $class;

	$self->{api_level} = 1 if (!defined($self->{api_level}));
	$self->{session_hash_function} = \&_dummy_session_hash_function
		if (!defined($self->{session_hash_function}));

	if ($self->{cap}) {
		$self->session_cap($self->{cap}) if (!$self->session_cap);
		$self->request_cap($self->{cap}) if (!$self->request_cap);
	}

	if (!$self->session_cap) {
		# XXX make adaptive the default once the logic is in place
		#$self->adaptive(1);

		$self->session_cap(10);
	}
	if (!$self->request_cap) {
		# XXX make adaptive the default once the logic is in place
		#$self->adaptive(1);

		$self->request_cap(10);
	}

	$self->{sessions} = [];
	$self->{running} = [];
	$self->{completed} = [];
	$self->{failed} = [];

	for ( 1 .. $self->session_cap) {
		push @{ $self->{sessions} },
			OpenSRF::AppSession->create(
				$self->{app},
				$self->{api_level},
				1
			);
		#print "Creating connection ".$self->{sessions}->[-1]->session_id." ...\n";
		$log->debug("Creating connection ".$self->{sessions}->[-1]->session_id." ...");
	}

	return $self;
}

sub _dummy_session_hash_function {
	my $self = shift;
	$self->{_dummy_hash_counter} = 1 if (!exists($self->{_dummy_hash_counter}));
	return $self->{_dummy_hash_counter}++;
}

sub connect {
	my $self = shift;
	$_->connect for (@{$self->{sessions}});
}

sub finish {
	my $self = shift;
	$_->finish for (@{$self->{sessions}});
}

sub disconnect {
	my $self = shift;
	$_->disconnect for (@{$self->{sessions}});
}

sub session_hash_function {
	my $self = shift;
	my $session_hash_function = shift;
	return unless (ref $self);

	$self->{session_hash_function} = $session_hash_function if (defined $session_hash_function);
	return $self->{session_hash_function};
}

sub failure_handler {
	my $self = shift;
	my $failure_handler = shift;
	return unless (ref $self);

	$self->{failure_handler} = $failure_handler if (defined $failure_handler);
	return $self->{failure_handler};
}

sub success_handler {
	my $self = shift;
	my $success_handler = shift;
	return unless (ref $self);

	$self->{success_handler} = $success_handler if (defined $success_handler);
	return $self->{success_handler};
}

sub session_cap {
	my $self = shift;
	my $cap = shift;
	return unless (ref $self);

	$self->{session_cap} = $cap if (defined $cap);
	return $self->{session_cap};
}

sub request_cap {
	my $self = shift;
	my $cap = shift;
	return unless (ref $self);

	$self->{request_cap} = $cap if (defined $cap);
	return $self->{request_cap};
}

sub adaptive {
	my $self = shift;
	my $adapt = shift;
	return unless (ref $self);

	$self->{adaptive} = $adapt if (defined $adapt);
	return $self->{adaptive};
}

sub completed {
	my $self = shift;
	my $count = shift;
	return unless (ref $self);


	if (wantarray) {
		$count ||= scalar @{$self->{completed}}; 
	}

	if (defined $count) {
		return () unless (@{$self->{completed}});
		return splice @{$self->{completed}}, 0, $count;
	}

	return scalar @{$self->{completed}};
}

sub failed {
	my $self = shift;
	my $count = shift;
	return unless (ref $self);


	if (wantarray) {
		$count ||= scalar @{$self->{failed}}; 
	}

	if (defined $count) {
		return () unless (@{$self->{failed}});
		return splice @{$self->{failed}}, 0, $count;
	}

	return scalar @{$self->{failed}};
}

sub running {
	my $self = shift;
	return unless (ref $self);
	return scalar(@{ $self->{running} });
}


sub request {
	my $self = shift;
	my $method = shift;
	my @params = @_;

	$self->session_reap;
	if ($self->running < $self->request_cap ) {
		my $index = $self->session_hash_function->($self, $method, @params);
		my $ses = $self->{sessions}->[$index % $self->session_cap]; 

		#print "Running $method using session ".$ses->session_id."\n";

		my $req = $ses->request( $method, @params );

		push @{ $self->{running} },
			{ req => $req,
			  meth => $method,
			  params => [@params]
			};

		$log->debug("Making request [$method] ".$self->running."...");

		return $req;
	} elsif (!$self->adaptive) {
		#print "Oops.  Too many running: ".$self->running."\n";
		$self->session_wait;
		return $self->request($method => @params);
	} else {
		# XXX do addaptive stuff ...
	}
}

sub session_wait {
	my $self = shift;
	my $all = shift;

	if ($all) {
		while ($self->running) {
			$self->session_reap;
		}
	} else {
		while(!$self->session_reap) {
			usleep 100;
		}
	}
}

sub session_reap {
	my $self = shift;

	my @done;
	my @running;
	while ( my $req = shift @{ $self->{running} } ) {
		if ($req->{req}->complete) {
			#print "Currently running: ".$self->running."\n";

			$req->{response} = [$req->{req}->recv];
			$req->{duration} = $req->{req}->duration;

			#print "Completed ".$req->{meth}." in session ".$req->{req}->session->session_id." [$req->{duration}]\n";

			if ($req->{req}->failed) {
				#print "ARG!!!! Failed command $req->{meth} in session ".$req->{req}->session->session_id."\n";
				$req->{error} = $req->{req}->failed;
				push @{ $self->{failed} }, $req;
			} else {
				push @{ $self->{completed} }, $req;
			}

			$req->{req}->finish;
			delete $$req{req};

			push @done, $req;

		} else {
			#print "Still running ".$req->{meth}." in session ".$req->{req}->session->session_id."\n";
			push @running, $req;
		}
	}
	push @{ $self->{running} }, @running;

	for my $req ( @done ) {
		my $handler = $req->{error} ? $self->failure_handler : $self->success_handler;
		$handler->($self, $req) if ($handler);
	}

	return scalar @done;
}

1;

