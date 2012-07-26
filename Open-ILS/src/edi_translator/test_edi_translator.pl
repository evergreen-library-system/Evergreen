#!/usr/bin/perl

# This assumes you have the translator (edi_webrick) running.

use strict;
use warnings;

use Data::Dumper;
use vars qw/$debug/;

use OpenILS::Utils::Cronscript;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Acq::EDI;
use OpenSRF::Utils::Logger q/$logger/;

INIT {
    $debug = 1;
}

my %defaults = (
    'quiet' => 0,
    'test'  => 0,
);

print "loading OpenILS environment... " if $debug;

my $cs = OpenILS::Utils::Cronscript->new(\%defaults);

my $opts = $cs->MyGetOptions;
my $e    = $cs->editor or die "Failed to get new CStoreEditor";

print "creating acq.edi_message object from stdin\n" if $debug;
my $message = new Fieldmapper::acq::edi_message;
$message->message_type("ORDERS");

my $input_field = $ENV{INPUT_IS_EDI} ? 'edi' : 'jedi';
my $output_field = $ENV{INPUT_IS_EDI} ? 'jedi' : 'edi';
{
    local $/;
    undef $/;
    $message->$input_field(<STDIN>);

}

print "calling out to edi translator... \n" if $debug;

my $r = attempt_translation OpenILS::Application::Acq::EDI($message, !$ENV{INPUT_IS_EDI});

if (!$r) {
    print STDERR "attempt_translation failed; see opensrf ERR logs\n";
} else {
    print $r->$output_field,"\n";
}

print "done.\n" if $debug;

