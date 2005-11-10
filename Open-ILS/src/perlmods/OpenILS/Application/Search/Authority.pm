package OpenILS::Application::Search::Authority;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::EX;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;

use JSON;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use Digest::MD5 qw(md5_hex);

sub crossref_subject {
	my $self = shift;
	my $client = shift;
	my $subject = shift;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	$session->connect;

	my $freq = $session->request('open-ils.storage.authority.subject.see_from.controlled.atomic',$subject);
	my $areq = $session->request('open-ils.storage.authority.subject.see_also_from.controlled.atomic',$subject);

	my $from = $freq->gather(1);
	my $also = $areq->gather(1);

	$session->disconnect;

	return { from => $from, also => $also };
}
__PACKAGE__->register_method(
        method		=> "crossref_subject",
        api_name	=> "open-ils.search.authority.subject.crossref",
        argc		=> 1, 
        note		=> "Searches authority data for existing subject controlled terms and crossrefs",
);              


1;
