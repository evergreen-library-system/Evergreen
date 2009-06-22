package OpenILS::WWW::AddedContent::OpenLibrary;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use OpenILS::WWW::AddedContent;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw/:try/;
use XML::LibXML;

# Edit the <added_content> section of /openils/conf/opensrf.xml
# Change <module> to:
#   <module>OpenILS::WWW::AddedContent::OpenLibrary</module>
# Change <base_url> to:
#   <base_url>http://covers.openlibrary.org/b/isbn/</base_url>


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
        $self->fetch_response('-S.jpg', $key));
}

sub jacket_medium {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('-M.jpg', $key));

}
sub jacket_large {
    my( $self, $key ) = @_;
    return $self->send_img(
        $self->fetch_response('-L.jpg', $key));
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
    my $url = $self->base_url . "$key$page";
    return $AC->get_url($url);
}



1;
