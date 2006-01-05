package OpenILS::Utils::SpiderMonkey;
use strict; use warnings;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::ScriptRunner;
use base 'OpenILS::Utils::ScriptRunner';
use JavaScript::SpiderMonkey;

sub new {
	my ( $class, $file ) = @_;
	$class = ref($class) || $class;
	my $self = { file => $file };
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
	$self->context($js);
	return $self;
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
		$logger->error("$file Eval failed: $@");  
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

sub insert_fm {

	my( $self, $key, $fm ) = @_;
	my $ctx = $self->context;
	return undef unless ($ctx and $key and $fm);
	my $o = $ctx->object_by_path($key);
	
	for my $f ( $fm->properties ) {
		$ctx->property_by_path("$key.$f", $fm->$f(),

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

sub insert_hash {

	my( $self, $key, $hash ) = @_;
	my $ctx = $self->context;
	return undef unless ($ctx and $key and $hash);
	$ctx->object_by_path($key);
	
	for my $k ( keys %$hash ) {
		$ctx->property_by_path(
			"$key.$k", $hash->{$k},
			sub { $hash->{_js_prop_name(shift())} },
			sub { 
				my( $key, $val ) = @_;
				$hash->{_js_prop_name($key)} = $val; }
		);
	}
}

1;
