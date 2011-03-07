package OpenILS::WWW::EGWeb::CGIUTF8;

# This is just a wrapper for TT around the real package,
# which is OpenILS::WWW::CGIUTF8

use strict;
use warnings;
use base 'Template::Plugin';
use OpenILS::WWW::CGIUTF8;

sub new {
    my $class   = shift;
    my $context = shift;
    new OpenILS::WWW::CGIUTF8(@_);
}

1;
