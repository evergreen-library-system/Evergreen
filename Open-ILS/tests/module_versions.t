use strict;
use warnings;

use Test::More tests => 1;

# check minimum required versions of Perl modules
BEGIN {
    use_ok('Encode', '2.13')
};
