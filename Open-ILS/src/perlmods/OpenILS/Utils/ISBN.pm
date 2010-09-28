package OpenILS::Utils::ISBN;

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

use Business::ISBN;

use base qw/Exporter/;
our $VERSION = '0.01';
our @EXPORT_OK = qw/isbn_upconvert/;

# Jason Stephenson <jstephenson@mvlc.org> at Merrimack Valley Library Consortium
# Dan Scott <dscott@laurentian.ca> at Laurentian University

sub isbn_upconvert {
    my $in     = @_ ? shift : return;
    my $pretty = @_ ? shift : 0;
    $in =~ s/\s*//g;
    $in =~ s/-//g;
    length($in) or return;
    my $isbn = Business::ISBN->new($in) or return;
    $isbn->fix_checksum() if $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM;
    $isbn->is_valid() or return;
    return $pretty ? $isbn->as_isbn13->as_string : $isbn->as_isbn13->isbn;
}

1;
__END__

For example, if you have a file isbns.txt with these lines:

1598884093
 1598884093
 15  988  840 93     
0446357197
  0 446 3 5  7 1 9        7
  0 446 3 5  7 1 9        1
0596526857
0786222735
0446360015
0446350109
0446314129
0439139597
0743294394
159143047X
1590203097
075480965X
0393048799
0446831832
0446310069
1598883275
0446313033
0446360279

And you run:
    perl -pe 'use OpenILS::Utils::ISBN qw/isbn_upconvert/; $_ = isbn_upconvert($_) . "\n";' <isbns.txt

You get this output:
9781598884098
9781598884098
9781598884098
9780446357197
9780446357197
9780446357197
9780596526856
9780786222735
9780446360012
9780446350105
9780446314121
9780439139595
9780743294393
9781591430476
9781590203095
9780754809654
9780393048797
9780446831833
9780446310062
9781598883275
9780446313032
9780446360272

