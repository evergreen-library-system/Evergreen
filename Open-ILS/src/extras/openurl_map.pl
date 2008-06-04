#!/usr/bin/perl
#

$|=1;

while (my $openurl = <>) {
	my $opensearch = '/opac/extras/opensearch/1.1/-/marcxml/-/?';
	my @parts = split('&', $openurl);

	my %params = (
		kw => '',
		au => '',
		ti => '',
	);

	for (@parts) {
		if (/^au[^=]+=(.*)$/o) {
			$params{au} .= $1 . ' ';
		} elsif (/^[sa]?title=(.*)$/o) {
			$params{ti} .= $1 . ' ';
		} elsif (/^e?is.n=(.*)$/o) {
			$params{kw} .= $1 . ' ';
		} elsif (/^[^=]+=(.*)$/o) {
			$params{kw} .= $1 . ' ';
		}
	}
	
	$opensearch .= join('&', map { "$_=$params{$_}" } keys %params );

	print $opensearch . "\n";

};
