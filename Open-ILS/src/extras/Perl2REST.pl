#!/usr/bin/perl -w
use strict;use warnings;
use OpenSRF::EX qw/:try/;
use JSON;
use OpenSRF::System;
use OpenSRF::Application;
use OpenILS::Utils::Fieldmapper;
use CGI;

$| = 1;

my $cgi = new CGI;
my $url = $cgi->url;

my $method = $cgi->param('method');
my $service = $cgi->param('service');
my @params = $cgi->param('param');

unless( $method ) {
	print "Content-Type: text/plain\n\n";
	print "usage:  $url?method={method}&param={param1}&param={param2}...\n";
	exit;
}

OpenSRF::System->bootstrap_client( config_file => '/pines/conf/bootstrap.conf' );
print "Content-Type: text/xml\n\n";

my $val = '';
try {
	my @resp;
	if ($service) {
		my $session = OpenSRF::AppSession->create($service);
		my $req = $session->request($method, @params);
		while (my $res = $req->recv) {
			push @resp, $res->content;
		}
	} else {
		$method = OpenSRF::Application->method_lookup( $method );
		@resp = $method->run(@params);
	}

	Perl2REST(\$val, $_, 1) for (@resp);
} catch Error with {
	print "<response/>";
	exit;
};

print "<response>\n" . $val . "</response>";


sub Perl2REST {
	my $val = shift;
	my $obj = shift;
	my $level = shift || 0;
	return unless defined($obj);
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
		(my $class_name = $class) =~ s/::/_/go;
		my $hint = $class->json_hint || $class_name;
		my $json = JSON->perl2JSON($obj);
		$json =~ s/&/&amp;/go;
		$json =~ s/</&lt;/go;
		$json =~ s/>/&gt;/go;
		my %hash;
		for ($obj->properties) {
			$hash{$_} = $obj->$_;
		}
		my $next = $level + 2;
		$$val .= '  'x$level . "<Fieldmapper hint='$hint' json='$json'>\n";
		for (sort keys %hash) {
			if ($hash{$_}) {
				$$val .= '  'x$level . "  <$_>\n";
				Perl2REST($val, $hash{$_}, $next);
				$$val .= '  'x$level . "  </$_>\n";
			} else {
				$$val .= '  'x$level . "  <$_/>\n";
			}
		}
		$$val .= '  'x$level . "</Fieldmapper>\n";

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
