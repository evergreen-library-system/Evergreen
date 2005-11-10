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

sub crossref_authority {
	my $self = shift;
	my $client = shift;
	my $class = shift;
	my $term = shift;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	$session->connect;

	my $freq = $session->request("open-ils.storage.authority.$class.see_from.controlled.atomic",$term);
	my $areq = $session->request("open-ils.storage.authority.$class.see_also_from.controlled.atomic",$term);

	my $fr = $freq->gather(1);
	my $al = $areq->gather(1);

	my %hash = ();
	for my $x (@$fr) {
		my $string = $$x[0];
		for my $i (1..10) {
			last unless ($$x[$i]);
			if ($string =~ /\W$/o) {
				$string .= ' '.$$x[$i];
			} else {
				$string .= ' -- '.$$x[$i];
			}
		}
		next if (lc($string) eq lc($term));
		$hash{$string}++;
	}
	my $from = [ sort { $hash{$b} <=> $hash{$a} || $a cmp $b } keys %hash ];

	%hash = ();
	for my $x (@$al) {
		my $string = $$x[0];
		for my $i (1..10) {
			last unless ($$x[$i]);
			if ($string =~ /\W$/o) {
				$string .= ' '.$$x[$i];
			} else {
				$string .= ' -- '.$$x[$i];
			}
		}
		next if (lc($string) eq lc($term));
		$hash{$string}++;
	}
	my $also = [ sort { $hash{$b} <=> $hash{$a} || $a cmp $b } keys %hash ];

	$session->disconnect;

	

	return { from => $from, also => $also };
}
__PACKAGE__->register_method(
        method		=> "crossref_authority",
        api_name	=> "open-ils.search.authority.crossref",
        argc		=> 2, 
        note		=> "Searches authority data for existing controlled terms and crossrefs",
);              


1;
