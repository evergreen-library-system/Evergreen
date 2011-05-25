#!/usr/bin/perl

# Copyright (C) 2011 Equinox Software, Inc.
# Galen Charlton <gmc@esilibrary.com>
#
# Make template for a new DB patch SQL file.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use warnings;

use Getopt::Long;

my $db_patch_num;
my $db_patch_nonum;
my $patch_name;
my $patch_from;
my $patch_wrap;
my @deprecates;
my @supersedes;

exit_usage() if $#ARGV == -1;
GetOptions( 
    'num=i' => \$db_patch_num,
    'nonum' => \$db_patch_nonum,
    'name=s' => \$patch_name,
    'from=s' => \$patch_from,
    'wrap=s' => \$patch_wrap,
    'deprecates=i' => \@deprecates,
    'supersedes=i' => \@supersedes,
) or exit_usage();

exit_usage('--num cannot be used with --nonum') if ($db_patch_nonum && defined $db_patch_num);
$db_patch_num = 'XXXX' if ($db_patch_nonum);
exit_usage('--num or --nonum required') unless defined $db_patch_num;
exit_usage('--name required') unless defined $patch_name;

$patch_from = 'HEAD' unless defined $patch_from;

# pad to four digits
$db_patch_num = sprintf('%-04.4d', $db_patch_num) unless $db_patch_nonum ;
$_ = sprintf('%-04.4d', $_) foreach @deprecates;
$_ = sprintf('%-04.4d', $_) foreach @supersedes;

if($db_patch_num ne 'XXXX') {
    # basic sanity checks
    my @existing = glob("upgrade/$db_patch_num.*");
    if (@existing) {    
        print "Error: $db_patch_num is already used by $existing[0]\n";
        exit(1);
    }
    foreach my $dep (@deprecates) {
        if ($dep gt $db_patch_num) {
            print "Error: deprecated patch $dep has a higher patch number than $db_patch_num\n";
            exit(1);
        }
    }
    foreach my $sup (@supersedes) {
        if ($sup gt $db_patch_num) {
            print "Error: superseded patch $sup has a higher patch number than $db_patch_num\n";
            exit(1);
        }
    }
}
else {
    if ( -e "upgrade/XXXX.$patch_name.sql" ) {
        print "Error: upgrade/XXXX.$patch_name.sql already exists\n";
        print "Either remove the existing file or pick a new --name\n";
        exit(1);
    }
}

my $patch_file_name = "upgrade/$db_patch_num.$patch_name.sql";
open OUT, '>', $patch_file_name or die "$): cannot open output file $patch_file_name: $!\n";

print OUT <<_HEADER_;
-- Evergreen DB patch $db_patch_num.$patch_name.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;

_HEADER_

if (@deprecates or @supersedes) {
    my @ins_cols = ('db_patch');
    my @ins_vals = ("'$db_patch_num'");
    if (@deprecates) {
        print OUT "-- Deprecates patch(es): " . join(', ', @deprecates) . "\n"; 
        push @ins_cols, 'deprecates';
        push @ins_vals, "ARRAY[" . join(', ', map { "'$_'" } @deprecates) . "]";
    }
    if (@supersedes) {
        print OUT "-- Supersedes patch(es): " . join(', ', @supersedes) . "\n";
        push @ins_cols, 'supersedes';
        push @ins_vals, "ARRAY[" . join(', ', map { "'$_'" } @supersedes) . "]";
    }
    print OUT "INSERT INTO config.db_patch_dependencies (" .
              join(', ', @ins_cols) .
              ")\nVALUES (" .
              join(', ', @ins_vals) .
              ");\n";
}

my $patch_init_contents;
$patch_init_contents = `git diff $patch_from -- ./[0-9][0-9][0-9].*.sql | sed -e '/^[^+\@-]/d' -e '/^\\(--- a\\|+++ b\\)/d' -e 's/^+//'` if ($patch_from ne '' && ! defined $patch_wrap);
$patch_init_contents = `cat $patch_wrap` if (defined $patch_wrap && $patch_wrap ne '');

print OUT <<_FOOTER_;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('$db_patch_num', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
$patch_init_contents

COMMIT;
_FOOTER_

close OUT;
print "Created new patch script $patch_file_name -- please go forth and edit.\n";

sub exit_usage {
    my $msg = shift;
    print "$msg\n\n" if defined($msg);
    print <<_HELP_;
usage: $0 --num <patch_num> --name <patch_name> [--deprecates <num1>] [--supersedes <num2>]

Make template for a DB patch SQL file.

    --num          DB patch number
    --nonum        Versionless
    --name         descriptive part of patch filename 
    --deprecates   patch(es) deprecated by this update
    --supersedes   patch(es) superseded by this update
    --from         git refspec to compare against
    --wrap         existing file to wrap (overrides --from)
_HELP_
    exit 0;
}
