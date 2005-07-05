#!/usr/bin/perl -w
use strict;use warnings;
use OpenSRF::System;
use OpenSRF::Application;
use OpenILS::Utils::Fieldmapper;
use CGI;

$| = 1;

my $cgi = new CGI;
my $url = $cgi->url;

my $method = $cgi->param('method');
my @params = $cgi->param('param');

unless( $method ) {
	print "Content-Type: text/plain\n\n";
	print "usage:  $url?method={method}&param={param1}&param={param2}...\n";
	exit;
}

print "Content-Type: text/xml\n\n";

OpenSRF::System->bootstrap_client( config_file => '/pines/conf/bootstrap.conf' );
$method = OpenSRF::Application->method_lookup( $method );

my @resp = $method->run(@params);

my $val = '';

Perl2REST(\$val, $_) for (@resp);

print $val;


sub Perl2REST {
	my $val = shift;
	my $obj = shift;
	my $level = shift || 0;
	if (!ref($obj)) {
		$$val .= '  'x$level . "<datum>$obj</datum>\n";
	} elsif (ref($obj) eq 'ARRAY') {
		my $next = $level + 1;
		$$val .= '  'x$level . "<array>\n";
		Perl2REST($val, $_, $next) for (@$obj);
		$$val .= '  'x$level . "</array>\n";
	} elsif (ref($obj) eq 'HASH') {
		my $next = $level + 2;
		$$val .= '  'x$level . "<hash>\n";
		for (sort keys %$obj) {
			$$val .= "  <pair>\n";
			$$val .= '  'x$level . "    <key>$_</key>\n";
			Perl2REST($val, $$obj{$_}, $next);
			$$val .= '  'x$level . "  </pair>\n";
		}
		$$val .= '  'x$level . "</hash>\n";
	} elsif (UNIVERSAL::isa($obj, 'Fieldmapper')) {
		my $class = ref($obj);
		$class =~ s/::/_/go;
		my %hash;
		for ($obj->properties) {
			$hash{$_} = $obj->$_;
		}
		my $next = $level + 2;
		$$val .= '  'x$level . "<$class>\n";
		for (sort keys %hash) {
			if ($hash{$_}) {
				$$val .= '  'x$level . "  <$_>\n";
				Perl2REST($val, $hash{$_}, $next);
				$$val .= '  'x$level . "  </$_>\n";
			} else {
				$$val .= '  'x$level . "  <$_/>\n";
			}
		}
		$$val .= '  'x$level . "</$class>\n";

	} elsif ($obj =~ /HASH/o) {
		my $class = ref($obj);
		$class =~ s/::/_/go;
		$$val .= '  'x$level . "<$class>\n";
		my $next = $level + 1;
		for (sort keys %$obj) {
			$$val .= "  <$_>\n";
			Perl2REST($val, $$obj{$_}, $next);
			$$val .= '  'x$level . "  </$_>\n";
		}
		$$val .= '  'x$level . "</$class>\n";
	} elsif ($obj =~ /ARRAY/o) {
		my $class = ref($obj);
		$class =~ s/::/_/go;
		my $next = $level + 1;
		$$val .= '  'x$level . "<$class>\n";
		Perl2REST($val, $_, $next) for (@$obj);
		$$val .= '  'x$level . "</$class>\n";
	} else {
		my $class = ref($obj);
		$class =~ s/::/_/go;
		$$val .= '  'x$level . "<$class>$obj</$class>\n";
	}
}
