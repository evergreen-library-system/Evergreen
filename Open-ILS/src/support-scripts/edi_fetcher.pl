#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright (C) 2010 Equinox Software, Inc
# Author: Joe Atzberger <jatzberger@esilibrary.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

use strict;
use warnings;

use Data::Dumper;
use vars qw/$debug/;

use OpenILS::Application::Acq::EDI;
use OpenILS::Utils::Cronscript;
use File::Spec;

my $defaults = {
    "account=i"  => 0,
    "provider=i" => 0,
    "inactive"   => 0,
    "test"       => 0,
};

my $core  = OpenILS::Utils::Cronscript->new($defaults);
my $opts  = $core->MyGetOptions() or die "Getting options failed!";
my $e     = $core->editor();
my $debug = $opts->{debug};

if ($debug) {
    print join "\n", "OPTIONS:", map {sprintf "%16s: %s", $_, $opts->{$_}} sort keys %$opts;
    print "\n\n";
}

sub main_search {
    my $select = {'+acqpro' => {active => {"in"=>['t','f']}} }; # either way
    my %args = @_ ? @_ : ();
    foreach (keys %args) {
        $select->{$_} = $args{$_};
    }
    return $e->search_acq_edi_account([
        $select,
        {
            'join' => 'acqpro',
            flesh => 1,
            flesh_fields => {acqedi => ['provider']},
        }
    ]);
}

my $set = main_search() or die "No EDI accounts found in database (table: acq.edi_account)";

my $total_accts = scalar(@$set);

($total_accts) or die "No EDI accounts found in database (table: acq.edi_account)";

print "EDI Accounts Total : $total_accts\n";
my $active = [ grep {$_->provider->active eq 't'} @$set ];
print "EDI Accounts Active: ", scalar(@$active), "\n";

my $subset;
if ($opts->{inactive} or $opts->{provider} or $opts->{account}) {
    print "Including inactive accounts\n";
    $subset = [@$set];
} else {
    $subset = $active;
}

my ($acct, $pro);
if ($opts->{provider}) {
    print "Limiting by provider: " . $opts->{provider} . "\n";
    $pro  = $e->retrieve_acq_provider($opts->{provider}) or die "provider '" . $opts->{provider} . "' not found";
    printf "Provider %s found (edi_default %s)\n", $pro->id, $pro->edi_default;
    $subset = main_search( 'id' => $pro->edi_default );
    # $subset = [ grep {$_->provider->id == $opts->{provider}} @$subset ];
    foreach (@$subset) {
        $_->provider($pro);     # force provider match (short of LEFT JOINing the main_search query and dealing w/ multiple combos)
    }
    scalar(@$subset) or die "provider '" . $opts->{provider} . "' edi_default invalid (failed to match acq.edi_account.id)";
    if ($opts->{account} and $opts->{account} != $pro->edi_default) {
        die sprintf "ERROR: --provider=%s and --account=%s specify rows that exist, but are not paired by acq.provider.edi_default", $opts->{provider}, $opts->{account};
    }
    $acct = $subset->[0]; 
} 
if ($opts->{account}) {
    print "Limiting by account: " . $opts->{account} . "\n";
    $subset = [ grep {$opts->{account}  == $_->id} @$subset ];
    scalar(@$subset) or die "No acq.provider.edi_default matches option  --account=" . $opts->{account} . " ";
    scalar(@$subset) > 1 and warn "account '" . $opts->{account} . "' has multiple matches.  Ignoring all but the first.";
    $acct = $subset->[0]; 
}
scalar(@$subset) or die "No acq.provider rows match options " .
    ($opts->{account}  ? ("--account="  . $opts->{account} ) : '') .
    ($opts->{provider} ? ("--provider=" . $opts->{provider}) : '') ;

print "Limiting to " . scalar(@$subset) . " account(s)\n"; 
foreach (@$subset) {
    printf "Provider %s - %s, edi_account %s - %s: %s%s\n",
        $_->provider->id, $_->provider->name, $_->id, $_->label, $_->host, ($_->in_dir ? ('/' . $_->in_dir) : '') ;
}

if (@ARGV) {
    $opts->{provider} or $opts->{account}
        or die "ERROR: --account=[ID] or --provider=[ID] option required for local data ingest, with valid edi_account or provider id";
    print "READING FROM ", scalar(@ARGV), " LOCAL SOURCE(s) ONLY.  NO REMOTE SERVER(s) WILL BE USED\n"; 
    printf "File will be attributed to edi_account %s - %s: %s\n", $acct->id, $acct->label, $acct->host;
    my @files = @ARGV; # copy original @ARGV
    foreach (@files) {
        @ARGV = ($_);  # We'll use the diamond op, so we can pull from STDIN too
        my $content = join '', <> or next;
        $opts->{test} and next;
        my $in = OpenILS::Application::Acq::EDI->process_retrieval(
            $content,
            "localhost:" . File::Spec->rel2abs($_),
            OpenILS::Application::Acq::EDI->remote_account($acct),
            $acct
        );
    }
    exit;
}
# else no args

my $res = OpenILS::Application::Acq::EDI->retrieve_core($subset,undef,undef,$opts->{test});
print "Files retrieved: ", scalar(@$res), "\n";
$debug and print "retrieve_core returns ", scalar(@$res),  " ids: " . join(', ', @$res), "\n";

# $Data::Dumper::Indent = 1;
$debug and print map {Dumper($_) . "\n"} @$subset;
print "\ndone\n";

__END__

=head1 NAME

edi_fetcher.pl - A script for retrieving and processing EDI files from remote accounts.

=head1 DESCRIPTION

This script is expected to be run via crontab, for the purpose of retrieving vendor EDI files.

Note: Depending on your vendors' and your own network environments, you may want to set/export
the environmental variable FTP_PASSIVE like:

    export FTP_PASSIVE=1
    # or
    FTP_PASSIVE=1 Open-ILS/src/support-scripts/edi_fetcher.pl

=head1 OPTIONS

  --account=[id]  Target one account, whether or not it is inactive.
  --inactive      Includes inactive provider accounts (default OFF, forced ON if --account specified)

=head1 ARGUMENTS

edi_fetcher can also read from files specified as arguments on the command line, or from STDIN, or both.
In such cases, the filename is not used to check whether the file has been loaded or not.  

=head1 TODO

More docs here.

=head1 SEE ALSO

    OpenILS::Utils::Cronscript
    edi_pusher.pl

=head1 AUTHOR

Joe Atzberger <jatzberger@esilibrary.com>

=cut

