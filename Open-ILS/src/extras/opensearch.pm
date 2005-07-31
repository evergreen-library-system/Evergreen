package opensearch;
use strict;
use warnings;

use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use LWP::UserAgent;

use CGI ();
use Template qw(:template);

use OpenSRF::EX qw(:try);
use OpenSRF::System;

sub handler {

	my $apache = shift;
	print "Content-type: text/xml; charset=utf-8\n\n";

	my $cgi = new CGI;
	
	if (my $fetch = $cgi->param('fetch')) {

		try {
			alarm(15);
			print LWP::UserAgent->new->get($fetch)->content;
			alarm(0);
		} catch Error with {
			alarm(0);
			print '<arg>';
		};
		alarm(0);

	} else {

		my $template = Template->new( { 
			OUTPUT			=> $apache, 
			ABSOLUTE			=> 1, 
			RELATIVE			=> 1,
			PLUGIN_BASE		=> 'OpenILS::Template::Plugin',
			INCLUDE_PATH	=> ['/openils/var/templates/'],
			PRE_CHOMP		=> 1,
			POST_CHOMP		=> 1,
			} 
		);

		try {
	
			if( ! $template->process( 'opensearch.ttk' ) ) { 
				warn "Error processing template opensearch.ttk\n";	
				warn  "Error Occured: " . $template->error();
				my $err = $template->error();
				$err =~ s/\n/\<br\/\>/g;
				print "<br><b>Unable to process template:<br/><br/> " . $err . "!!!</b>";
			}

		} catch Error with {
			my $e = shift;
			warn "Error processing template opensearch.ttk:  $e - $@ \n";	
			print "<center><br/><br/><b>Error<br/><br/> $e <br/><br/> $@ </b><br/></center>";
			return;
		};
	}
	return Apache2::Const::OK;
}

1;
