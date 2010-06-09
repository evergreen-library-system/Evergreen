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
use OpenILS::Utils::CStoreEditor;   # needs init() after IDL is loaded (by Cronscript session)
use OpenILS::Utils::Cronscript;

INIT {
    $debug = 1;
}

OpenILS::Utils::Cronscript->new()->session('open-ils.acq') or die "No session created";
OpenILS::Utils::CStoreEditor::init();

sub editor {
    my $ed = OpenILS::Utils::CStoreEditor->new(@_) or die "Failed to get new CStoreEditor";
    return $ed;
}


my $e = editor();
my $set = $e->retrieve_all_acq_edi_account();
my $total_accts = scalar(@$set);

($total_accts) or die "No EDI accounts found in database (table: acq.edi_account)";

print "EDI Accounts Total : ", scalar(@$set), "\n";

my $subset = $e->search_acq_edi_account([
    {'+acqpro' => {active => 't'}},
    {
        'join' => 'acqpro',
        flesh => 1,
        flesh_fields => {acqedi => ['provider']},
    }
]);

print "EDI Accounts Active: ", scalar(@$subset), "\n";

my $res = OpenILS::Application::Acq::EDI->retrieve_core();
print "Files retrieved: ", scalar(@$res), "\n";
$debug and print "retrieve_core returns ", scalar(@$res),  " ids: " . join(', ', @$res), "\n";

$debug and print Dumper($set);
print "\ndone\n";
