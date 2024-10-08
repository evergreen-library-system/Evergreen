#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Test::More;
use FindBin;

sub is_modern_upgrade_script {
  my $script_id = (split /\./, shift)[0];
  unless (defined $script_id) { return 0; }
  return ($script_id =~ /^[xy]{4}$/i) || ($script_id > 1236);
}

my $directory_path = "$FindBin::Bin/../../../sql/Pg/upgrade";

opendir my $dir, $directory_path or croak "Cannot open directory: $!";
my @upgrade_scripts = readdir $dir;
closedir $dir;
my @modern_upgrade_scripts = grep is_modern_upgrade_script($_), @upgrade_scripts;
plan tests => scalar @modern_upgrade_scripts + 1;

ok(scalar @modern_upgrade_scripts > 175, 'We have a reasonable number of modern upgrade scripts');

foreach(@modern_upgrade_scripts) {
    my $found = 0;
    my $file = "$directory_path/$_";
    open my $fh, "<", $file or croak $_;

    while (my $line = <$fh>) {
        if ($line =~ /SELECT evergreen.upgrade_deps_block_check.*:eg_version/i) {
            $found = 1;
        }
    }

    ok($found, "Upgrade script $_ has a valid upgrade deps block check");

    close $fh;
}
