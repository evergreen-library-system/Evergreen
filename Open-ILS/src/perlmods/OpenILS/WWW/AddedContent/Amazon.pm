package OpenILS::WWW::AddedContent::Amazon;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenILS::WWW::AddedContent;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use XML::LibXML;

my $AC = 'OpenILS::WWW::AddedContent';

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless($args, $class);
}

sub base_url {
    my $self = shift;
    return $self->{base_url};
}

sub userid {
    my $self = shift;
    return $self->{userid};
}


# --------------------------------------------------------------------------
sub jacket_small {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('_SCMZZZZZZZ_.jpg', $key));
}

sub jacket_medium {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('_SCMZZZZZZZ_.jpg', $key));

}
sub jacket_large {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('_SCZZZZZZZ_.jpg', $key));
}

# --------------------------------------------------------------------------

sub toc_html {
    my( $self, $key ) = @_;
}

sub toc_xml {
    my( $self, $key ) = @_;
}

sub toc_json {
    my( $self, $key ) = @_;
}

# --------------------------------------------------------------------------

sub anotes_html {
    my( $self, $key ) = @_;
}

sub anotes_xml {
    my( $self, $key ) = @_;
}

sub anotes_json {
    my( $self, $key ) = @_;
}


# --------------------------------------------------------------------------

sub excerpt_html {
    my( $self, $key ) = @_;
}

sub excerpt_xml {
    my( $self, $key ) = @_;
}

sub excerpt_json {
    my( $self, $key ) = @_;
}

# --------------------------------------------------------------------------

sub reviews_html {
    my( $self, $key ) = @_;
}

# we have to aggregate the reviews
sub reviews_xml {
    my( $self, $key ) = @_;
}


sub reviews_json {
    my( $self, $key ) = @_;
}

# --------------------------------------------------------------------------

sub send_img {
    my($self, $response) = @_;
    return { 
        content_type => $response->header('Content-type'),
        content => $response->content, 
        binary => 1 
    };
}

# returns the raw content returned from the URL fetch
sub fetch_content {
    my( $self, $page, $key ) = @_;
    return $self->fetch_response($page, $key)->content;
}

# returns the HTTP response object from the URL fetch
sub fetch_response {
    my( $self, $page, $key ) = @_;
    my $uname = $self->userid;
    my $url = $self->base_url . "$key.01.$page";
    return $AC->get_url($url);
}



1;
