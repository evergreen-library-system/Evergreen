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

use strict; use warnings;
use vars qw/ $session $e $i $call/;

use Test::More qw/no_plan/;

sub nappy {
    if (@ARGV) {
        my $nap = shift @ARGV;
        diag("OK, this time we'll sleep for $nap seconds to see if CStore wakes up");
        sleep $nap;
    }
}

BEGIN {
    $i = 5;
    $call = 'retrieve_all_acq_edi_account';
    use_ok('OpenILS::Utils::Cronscript');
    ok($session = OpenILS::Utils::Cronscript->new()->session('open-ils.acq'),
        "new session created");
}

INIT {
    nappy();
    use_ok('OpenILS::Utils::CStoreEditor');
}

nappy();

ok($e = OpenILS::Utils::CStoreEditor->new(xact => 1),
    "new CStoreEditor created");

until (can_ok($e, $call) or $i-- == 0) {
    diag("CStore FAIL: cannot $call");
    sleep 2;
    diag("reloading: prepare for a ton of warnings");
    delete $INC{'OpenILS/Utils/CStoreEditor.pm'};
    require_ok('OpenILS::Utils::CStoreEditor');
    diag("reloaded");
    ok($e = OpenILS::Utils::CStoreEditor->new(xact => 1),
        "replacement CStoreEditor created");
}

my $set = $e->retrieve_all_acq_edi_account();
ok(defined($set), $call);
print "\ndone\n";

