#!/usr/bin/perl -w
use strict;use warnings;
use OpenSRF::System qw(/pines/conf/client.conf);
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Fieldmapper;
use Time::HiRes (qw/time/);

$| = 1;

# ----------------------------------------------------------------------------------------
# This is a quick and dirty script to perform benchmarking against the math server.
# Note: 1 request performs a batch of 4 queries, one for each supported method: add, sub,
# mult, div.
# Usage: $ perl math_bench.pl <num_requests>
# ----------------------------------------------------------------------------------------


my $method = shift;

unless( $method ) {
	print "usage: $0 method\n";
	exit;
}

OpenSRF::System->bootstrap_client();
$method = OpenSRF::Application->method_lookup( $method );
my $resp = $method->run(@ARGV);

#my $usr = new Fieldmapper::actor::user;
#$usr->first_given_name('mike');
#$usr->family_name('rylander');
#
#my $addr = new Fieldmapper::actor::user_address;
#$addr->street1('123 main st');
#$addr->post_code('30144');
#
#$usr->billing_address($addr);

#my $resp =  {
#	a => 'hash',
#	b => 'value',
#	c => { nested => 'hash' },
#	d => [ qw/with an array inside/ ],
#	e => $usr,
#};

my $val = '';

my $start = time;
Perl2REST(\$val, $resp);
my $end = time;

print $val;
print "\nTIME: ". ($end - $start) . "s\n";


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

	} elsif (ref($obj) =~ /HASH/o) {
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
	} elsif (ref($obj) =~ /ARRAY/o) {
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
