package OpenILS::WWW::CGIUTF8;
use strict;
use warnings;
use base qw(CGI);
use Encode;

sub param {
    my ($self, $k) = @_;

    return map { Encode::decode_utf8($_) } CGI::param($k) if wantarray;
    return Encode::decode_utf8(CGI::param($k));
}

sub param_bin {
    my $self = shift;

    return CGI::param(@_);
}

1;
