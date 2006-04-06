#!/usr/bin/perl
use lib '/openils/lib/perl5/';
use OpenSRF::System;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::EX qw/:try/;
use JSON;
use Data::Dumper;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils qw/:daemon/;
use OpenSRF::MultiSession;
use OpenSRF::AppSession;
use Time::HiRes qw/time/;
use JSON;

my $config = shift;

unless (-e $config) {
	die "Gimme a config file!!!";
}
OpenSRF::System->bootstrap_client( config_file => $config );

if (!@ARGV) {
	@ARGV = ('open-ils.storage','opensrf.system.echo');
}

my $app = shift;

my $count = 100;

my $overhead = time;

my $mses = OpenSRF::MultiSession->new( app => $app, cap => 10, api_level => 1 );

$mses->success_handler(
	sub {
		my $ses = shift;
		my $req = shift;
		print $req->{params}->[0] . "\t: " . JSON->perl2JSON($req->{response}->[0]->content)."\n";
	}
);

$mses->failure_handler(
	sub {
		my $ses = shift;
		my $req = shift;
		warn "record $req->{params}->[0] failed: ".JSON->perl2JSON($req->{response});
	}
);


$mses->connect;

my $start = time;
$overhead = $start - $overhead;

for (1 .. $count) {
	$mses->request( @ARGV,$_ );
}
$mses->session_wait(1);
$mses->disconnect;

my $end = time;

my @c = $mses->completed;
my @f = $mses->failed;

my $x = 0;
$x += $_->{duration} for (@c);

print "\n". '-'x40 . "\n";
print "Startup Overhead: ".sprintf('%0.3f',$overhead)."s\n";
print "Completed Commands: ".@c."\n";
print "Failed Commands: ".@f."\n";
print "Serial Run Time: ".sprintf('%0.3f',$x)."s\n";
print "Serial Avg Time: ".sprintf('%0.3f',$x/$count)."s\n";
print "Total Run Time: ".sprintf('%0.3f',$end-$start)."s\n";
print "Total Avg Time: ".sprintf('%0.3f',($end-$start)/$count)."s\n";

