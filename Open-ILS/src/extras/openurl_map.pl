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
        searchOrg => '',
        searchSort => '',
        searchSortDir => '',
        searchLang => '',
        startIndex => '',
        count => '',
	);

	for (@parts) {
		if (/^au[^=]+=(.*)$/o) {
			$params{au} .= $1 . ' ';
		} elsif (/^[sa]?title=(.*)$/o) {
			$params{ti} .= $1 . ' ';
		} elsif (/^e?is.n=(.*)$/o) {
			$params{kw} .= $1 . ' ';
		} elsif (/^searchSort=(.*)$/o) {
			$params{searchSort} = $1;
		} elsif (/^searchSortDir=(.*)$/o) {
			$params{searchSortDir} = $1;
		} elsif (/^searchLang=(.*)$/o) {
			$params{searchLang} = $1;
		} elsif (/^startIndex=(.*)$/o) {
			$params{startIndex} = $1;
		} elsif (/^count=(.*)$/o) {
			$params{count} = $1;
		} elsif (/^searchOrg=(.*)$/o) {
			$params{searchOrg} = $1;
		} elsif (/^[^=]+=(.*)$/o) {
			$params{kw} .= $1 . ' ';
		}
	}
	
	$opensearch .= join('&', map { "$_=$params{$_}" } keys %params );

	print $opensearch . "\n";

};
