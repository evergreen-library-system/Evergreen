package OpenILS::WWW::XMLRPCGateway;
use strict; use warnings;

use CGI;
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use Data::Dumper;
use UNIVERSAL::require;

use XML::LibXML;
use OpenSRF::EX qw(:try);
use OpenSRF::System;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsClient;

use RPC::XML qw/smart_encode/;
use RPC::XML::Parser;
use RPC::XML::Function;
use RPC::XML::Method;
use RPC::XML::Procedure;

$RPC::XML::ENCODING = 'utf-8';

my $services; 						# allowed services
my $CLASS_KEY = '__class__';	# object wrapper class key
my $PAYLOAD_KEY = '__data__';	# object wrapper payload key
my $bs_config; 					# bootstrap config
my $__inited = 0; 				# has child_init run?


# set the bootstrap config when this module is loaded
sub import { $bs_config = $_[1]; }


# Bootstrap and load config settings
sub child_init {
	$__inited = 1;
	OpenSRF::AppSession->ingress('xmlrpc');
	OpenSRF::System->bootstrap_client( config_file => $bs_config );
	my $sclient	= OpenSRF::Utils::SettingsClient->new();
	my $idl = $sclient->config_value("IDL");
	$services = $sclient->config_value("xml-rpc", "allowed_services", "service");
	$services = ref $services ? $services : [ $services ];
	$logger->debug("XML-RPC: allowed services @$services");
	OpenILS::Utils::Fieldmapper->require;
	Fieldmapper->import(IDL => $idl);
	OpenSRF::AppSession->ingress('apache');
	return Apache2::Const::OK;
}


sub handler {

	my $r		= shift;
	my $cgi	= CGI->new;
	my $service = $r->path_info;
	$service =~ s#^/##;

	child_init() unless $__inited; # ?

	return Apache2::Const::NOT_FOUND unless grep { $_ eq $service } @$services;

	my $request = RPC::XML::Parser->new->parse($cgi->param('POSTDATA'));

	my @args;
	push( @args, unwrap_perl($_->value) ) for @{$request->args};
	my $method = $request->name;

	warn "XML-RPC: service=$service, method=$method, args=@args\n";
	$logger->debug("XML-RPC: service=$service, method=$method, args=@args");

	my $perl = run_request( $service, $method, @args );
	my $resp = RPC::XML::response->new(smart_encode($perl));

	print "Content-type: application/xml; charset=utf-8\n\n";
	print $resp->as_string;
	return Apache2::Const::OK;
}


sub run_request {
    my( $service, $method, @args ) = @_;

    # since multiple Perl clients run within mod_perl, 
    # we must set our ingress before each request.
    OpenSRF::AppSession->ingress('xmlrpc');

    my $ses = OpenSRF::AppSession->create( $service );

    my $data = [];
    my $req = $ses->request($method, @args);
    while( my $resp = $req->recv( timeout => 600 ) ) {
        if( $req->failed ) {
            push( @$data, $req->failed );
            last;
        }
        push( @$data, $resp->content );
    }

    # recover the default Apache/http ingress to avoid 
    # polluting other mod_perl clients w/ our ingress value.
    OpenSRF::AppSession->ingress('apache');

    return [] if scalar(@$data) == 0;
    return wrap_perl($$data[0]) 
        if scalar(@$data) == 1 and $method !~ /.atomic$/og;
    return wrap_perl($data);
}

# These should probably be moved out to a library somewhere

sub wrap_perl {
   my $obj = shift;
   my $ref = ref($obj);

   if ($ref =~ /^Fieldmapper/o) {
      $ref = $obj->json_hint;
      $obj = $obj->to_bare_hash;
   }

   if( $ref eq 'HASH' ) {
      $obj->{$_} = wrap_perl( $obj->{$_} ) for (keys %$obj);
   } elsif( $ref eq 'ARRAY' ) {
      $obj->[$_] = wrap_perl( $obj->[$_] ) for(0..scalar(@$obj) - 1 );
   } elsif( $ref ) {
      if(UNIVERSAL::isa($obj, 'HASH')) {
         $obj->{$_} = wrap_perl( $obj->{$_} ) for (keys %$obj);
         bless($obj, 'HASH'); # so our parser won't add the hints
      } elsif(UNIVERSAL::isa($obj, 'ARRAY')) {
         $obj->[$_] = wrap_perl( $obj->[$_] ) for(0..scalar(@$obj) - 1);
         bless($obj, 'ARRAY'); # so our parser won't add the hints
      }
      $obj = { $CLASS_KEY => $ref, $PAYLOAD_KEY => $obj };
   }
   return $obj;
}



sub unwrap_perl {
   my $obj = shift;
   my $ref = ref($obj);
   if( $ref eq 'HASH' ) {
      if( defined($obj->{$CLASS_KEY})) {
         my $class = $obj->{$CLASS_KEY};
         if( $obj = unwrap_perl($obj->{$PAYLOAD_KEY}) ) {
            return bless(\$obj, $class) unless ref($obj);
            return bless( $obj, $class );
         }
         return undef;
      }
      $obj->{$_} = unwrap_perl( $obj->{$_} ) for (keys %$obj);
   } elsif( $ref eq 'ARRAY' ) {
      $obj->[$_] = unwrap_perl($obj->[$_]) for(0..scalar(@$obj) - 1);
   }
   return $obj;
}




1;
