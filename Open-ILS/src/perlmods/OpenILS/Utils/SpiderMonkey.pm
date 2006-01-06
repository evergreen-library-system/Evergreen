package OpenILS::Utils::SpiderMonkey;
use strict; use warnings;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::ScriptRunner;
use base 'OpenILS::Utils::ScriptRunner';
use JavaScript::SpiderMonkey;

sub new {
	my ( $class, %params ) = @_;
	$class = ref($class) || $class;
	my $self = { file => $params{file}, libs => $params{libs} };
	return bless( $self, $class );
}

sub context {
	my( $self, $context ) = @_;
	$self->{ctx} = $context if $context;
	return $self->{ctx};
}

sub init {
	my $self = shift;
	my $js = JavaScript::SpiderMonkey->new();
	$js->init();
	$js->function_set("perl_print",		sub { print "@_\n"; } );
	$js->function_set("log_error",		sub { $logger->error(@_); return 1;} );
	$js->function_set("log_warn",			sub { $logger->warn(@_); return 1;} );
	$js->function_set("log_info",			sub { $logger->info(@_); return 1;} );
	$js->function_set("log_debug",		sub { $logger->debug(@_); return 1;} );
	$js->function_set("log_internal",	sub { $logger->internal(@_); return 1;} );
	$js->function_set("debug",				sub { $logger->debug(@_); return 1;} );
	$js->function_set("alert",				sub { $logger->warn(@_); return 1;} );
	$self->context($js);
	$self->load_lib($_) for @{$self->{libs}};
}


sub load {
	my( $self, $filename ) = @_;
	$self->{file} = $filename;
}

sub run {
	my $self = shift;
	my $file = shift() || $self->{file};
	my $js = $self->context;

	if( ! open(F, $file) ) {
		$logger->error("Error opening script file: $file");
		return 0;
	}

	if( ! $js->eval(join("\n", <F>)) ) {
		$logger->error("Script ($file) eval failed in SpiderMonkey run: $@");  
		return 0;
	}

	close(F);
	return 1;
}

sub load_lib { 
	my( $self, $file ) = @_;
	$self->run( $file );
}

sub _js_prop_name {
	my $name = shift;
	$name =~ s/^.*\.//o;
	return $name;
}

sub retrieve {
	my( $self, $key ) = @_;
	return $self->context->property_get($key);
}

sub insert {
	my( $self, $key, $val ) = @_;
	return unless defined($val);

	if (ref($val) =~ /^Fieldmapper/o) {
		$self->insert_fm($key, $val);
	} elsif (ref($val) and $val =~ /ARRAY/o) {
		$self->insert_array($key, $val);
	} elsif (ref($val) and $val =~ /HASH/o) {
		$self->insert_hash($key, $val);
	} elsif (!ref($val)) {
		$self->context->property_by_path(
			$key, $val,
			sub { $val },
			sub { my( $k, $v ) = @_; $val = $v; }
		);
	} else {
		return 0;
	}

	return 1;
}

sub insert_fm {

	my( $self, $key, $fm ) = @_;
	my $ctx = $self->context;
	return undef unless ($ctx and $key and $fm);
	my $o = $ctx->object_by_path($key);
	
	for my $f ( $fm->properties ) {
		my $val = $fm->$f();
		if (ref $val) {
			$self->insert("$key.$f", $val);
		} else {
			$ctx->property_by_path(
				"$key.$f",
				$val,
				sub {
					my $k = _js_prop_name(shift());
					$fm->$k();
				}, 

				sub {
					my $k = _js_prop_name(shift());
					$fm->ischanged(1);
					$fm->$k(@_);
				}
			);
		}
	}
}

sub insert_hash {

	my( $self, $key, $hash ) = @_;
	my $ctx = $self->context;
	return undef unless ($ctx and $key and $hash);
	$ctx->object_by_path($key);
	
	for my $k ( keys %$hash ) {
		my $v = $hash->{$k};
		if (ref $v) {
			$self->insert("$key.$k", $v);
		} else {
			$ctx->property_by_path(
				"$key.$k", $v,
				sub { $hash->{_js_prop_name(shift())} },
				sub { 
					my( $key, $val ) = @_;
					$hash->{_js_prop_name($key)} = $val; }
			);
		}
	}
}

sub insert_array {

	my( $self, $key, $array ) = @_;
	my $ctx = $self->context;
	return undef unless ($ctx and $key and $array);

	my $a = $ctx->array_by_path($key);
	
	my $ind = 0;
	for my $v ( @$array ) {
		if (ref $v) {
			my $elobj = $ctx->object_by_path('__tmp_arr_el');
			$self->insert('__tmp_arr_el', $v);
			$ctx->array_set_element_as_object( $a, $ind, $elobj );
		} else {
			$ctx->array_set_element( $a, $ind, $v ) if defined($v);
		}
		$ind++;
	}
}

1;
