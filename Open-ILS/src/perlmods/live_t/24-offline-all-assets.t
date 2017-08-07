#!perl

use Test::More tests => 1;

my $command = = 'wget --no-check-certificate -m https://localhost/eg/staff/offline-interface/session 2>&1 |grep -B 2 404|grep https|grep -v robots.txt|wc -l'
is(`$command`, '0', "No missing assets required by the offline interface");

