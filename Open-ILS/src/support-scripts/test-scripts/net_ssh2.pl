#!/usr/bin/perl
#

use strict;
use warnings;

use Test::More qw/no_plan/;

my %config = (
    hostname   => @ARGV ? shift @ARGV : 'example.org',
    username   => @ARGV ? shift @ARGV : 'some_user',
    file       => @ARGV ? shift @ARGV : '.bashrc',
    privatekey => glob("~/.ssh/id_rsa") || glob("~/.ssh/id_dsa"),
);
$config{publickey} = $config{privatekey} . '.pub';

BEGIN {
    use_ok( 'Net::SSH2'  );
    use_ok( 'IO::Scalar' );
    use_ok( 'IO::File'   );
    use_ok( 'File::Glob', qw/:glob/ );
}

my $ssh;

ok($ssh = Net::SSH2->new,
         'Net::SSH2->new');

ok($ssh->connect( $config{hostname} ),
   "ssh->connect('$config{hostname}')");

ok($ssh->auth_publickey(@config{qw/username publickey privatekey/}),
   "ssh->auth_publickey("
        . join(', ', map{"'$_'"} @config{qw/username publickey privatekey/})
   . ")"
);

my (@list, $io, $iofile);

my $scalar = "## This line starts in the variable before we read the file\n## This line too.\n";

ok($io     = IO::Scalar->new(\$scalar), "IO::Scalar->new");
ok($iofile = IO::File->new(">/tmp/io_file.tmp"),
            "IO::File->new('>/tmp/io_file.tmp')");

ok($ssh->scp_get($config{file},  $io),
   "ssh->scp_get($config{file}, \$io) # trying to retrieve file into IO::Scalar"
);

diag("Now printing remote file from IO::Scalar:");
print $io;

