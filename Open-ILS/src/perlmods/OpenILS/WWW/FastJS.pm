package OpenILS::WWW::FastJS;
use strict; use warnings;

use Apache2 ();
use Apache::Log;
use Apache::Const -compile => qw(OK REDIRECT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache::RequestRec ();
use Apache::RequestIO ();
use Apache::RequestUtil;

use CGI ();
use Template qw(:template);

use OpenSRF::EX qw(:try);


my $main_ttk = "opac/logic/fastjs.ttk";
my $init_ttk = "opac/logic/page_init.ttk";

my $includes = ['/pines/cvs/ILS/Open-ILS/src/templates'];

my $plugin_base = 'OpenILS::Template::Plugin';

sub handler {

	my $apache = shift;
	my $cgi = CGI->new( $apache );
	print "Content-type: text/javascript; charset=utf-8\n\n";
	
	my @files = $cgi->param("file");
	warn "INcluding js files @files\n";

	_process_template(
			apache		=> $apache,
			template		=> $main_ttk,
			pre_process	=> $init_ttk,
			files			=> \@files,
			);

	return Apache::OK;
}

sub _process_template {

	my %params = @_;
	my $ttk				= $params{template}		|| return undef;
	my $apache			= $params{apache}			|| undef;
	my $pre_process	= $params{pre_process}	|| undef;
	my $files			= $params{files}			|| [];

	my $template;

	$template = Template->new( { 
		OUTPUT			=> $apache, 
		ABSOLUTE			=> 1, 
		RELATIVE			=> 1,
		PLUGIN_BASE		=> $plugin_base,
		PRE_PROCESS		=> $pre_process,
		INCLUDE_PATH	=> $includes, 
		PRE_CHOMP		=> 1,
		POST_CHOMP		=> 1,
		} 
	);

	try {

		if( ! $template->process( $ttk, 
				{ files => $files, doc_root => $ENV{"DOCUMENT_ROOT"} }  ) ) { 

			warn  "Error Occured: " . $template->error();
			my $err = $template->error();
			$err =~ s/\n/\<br\/\>/g;
			warn "Error processing template $ttk\n";	
			my $string =  "<br><b>Unable to process template:<br/><br/> " . $err . "!!!</b>";
			#$template->process( $error_ttk , { error => $string } );
		}

	} catch Error with {
		my $e = shift;
		warn "Error processing template $ttk:  $e - $@ \n";	
		print "<center><br/><br/><b>Error<br/><br/> $e <br/><br/> $@ </b><br/></center>";
		return;
	};

}


1;
