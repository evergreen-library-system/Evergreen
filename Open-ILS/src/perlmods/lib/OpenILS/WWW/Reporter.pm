package OpenILS::WWW::Reporter;
use strict; use warnings;

use vars qw/$dtype_xform_map $dtype_xform/;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;

use Template;

use OpenSRF::EX qw(:try);
use OpenSRF::System;
use XML::LibXML;

use OpenSRF::Utils::SettingsParser;
use OpenILS::Utils::Fieldmapper;
use OpenILS::WWW::Reporter::transforms;


# set the bootstrap config and template include directory when 
# this module is loaded
my $bootstrap;
my $includes = [];  
my $base_xml;
#my $base_xml_doc;

sub import {
	my( $self, $bs_config, $core_xml, @incs ) = @_;
	$bootstrap = $bs_config;
	$base_xml = $core_xml;
	$includes = [ @incs ];
}


# our templates plugins are here
my $plugin_base = 'OpenILS::Template::Plugin';

sub child_init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap );

	#parse the base xml file
	#my $parser = XML::LibXML->new;
	#$parser->expand_xinclude(1);

	#$base_xml_doc = $parser->parse_file($base_xml);
	return Apache2::Const::OK;
}

sub handler {

	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = CGI->new;

	my $path = $apache->path_info;
	(my $ttk = $path) =~ s{^/?([a-zA-Z0-9_]+).*?$}{$1}o;

	$ttk = $apache->filename unless $ttk;
	$ttk = "dashboard" unless $ttk;

	$ttk = (split '/', $ttk)[-1];
	
	my $user;

	# if the user is not logged in via cookie, route them to the login page
	if(! ($user = verify_login($cgi->cookie("ses"))) ) {
		$ttk = "login";
	}


	print "Content-type: text/html; charset=utf-8\n\n";
	#print "Content-type: text/html\n\n";

	_process_template(
			apache		=> $apache,
			template		=> "$ttk.ttk",
			params		=> { 
				user => $user, 
				stage_dir => $ttk, 
				config_xml => $base_xml, 
				},
			);

	return Apache2::Const::OK;
}


sub _process_template {

	my %params = @_;
	my $ttk				= $params{template}		|| return undef;
	my $apache			= $params{apache}			|| undef;
	my $param_hash		= $params{params}			|| {};
	$$param_hash{dtype_xform_map} = $OpenILS::WWW::Reporter::dtype_xform_map;
	$$param_hash{dtype_xforms} = $OpenILS::WWW::Reporter::dtype_xforms;

	my $template;

	$template = Template->new( { 
		OUTPUT			=> $apache, 
		ABSOLUTE		=> 1, 
		RELATIVE		=> 1,
		PLUGIN_BASE		=> $plugin_base,
		INCLUDE_PATH	=> $includes, 
		PRE_CHOMP		=> 1,
		POST_CHOMP		=> 1,
		#LOAD_PERL		=> 1,
		} 
	);

	try {

		if( ! $template->process( $ttk, $param_hash ) ) { 
			warn  "Error Processing Template: " . $template->error();
			my $err = $template->error();
			$err =~ s/\n/\<br\/\>/g;
			warn "Error processing template $ttk\n";	
			my $string =  "<br><b>Unable to process template:<br/><br/> " . $err . "</b>";
			print "ERROR: $string";
			#$template->process( $error_ttk , { error => $string } );
		}

	} catch Error with {
		my $e = shift;
		warn "Error processing template $ttk:  $e - $@ \n";	
		print "<center><br/><br/><b>Error<br/><br/> $e <br/><br/> $@ </b><br/></center>";
		return;
	};

}

# returns the user object if the session is valid, 0 otherwise
sub verify_login {
	my $auth_token = shift;
	return 0 unless $auth_token;

	my $session = OpenSRF::AppSession->create("open-ils.auth");
	my $req = $session->request(
		"open-ils.auth.session.retrieve", $auth_token );
	my $user = $req->gather(1);

	if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
		return 0;
	}

	return $user if ref($user);
	return 0;
}



1;
