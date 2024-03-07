package OpenILS::WWW::EResourceLinkClick;

use strict;
use warnings;

use OpenILS::Application::EResourceLinkClick;
use Apache2::Const -compile => qw(
    OK HTTP_BAD_REQUEST HTTP_INTERNAL_SERVER_ERROR HTTP_NOT_IMPLEMENTED
);
use CGI;

sub handler {
    my $r = shift;
    my $cgi = new CGI;

    my $record_id = $cgi->param('record_id') || '';
    my $url = $cgi->param('url') || '';
    my $referer = $cgi->http('Referer') || '';
    my $user_agent = $cgi->http('User-Agent') || '';

    my $result = OpenILS::Application::EResourceLinkClick->add_click(
        $record_id,
        $url,
        $referer,
        $user_agent
    );

    if( $result eq OpenILS::Application::EResourceLinkClick::BadInput ) {
        return Apache2::Const::HTTP_BAD_REQUEST;
    }
    if( $result eq OpenILS::Application::EResourceLinkClick::InternalError ) {
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }
    if( $result eq OpenILS::Application::EResourceLinkClick::NotConfigured ) {
        return Apache2::Const::HTTP_NOT_IMPLEMENTED;
    }
    if( $result eq OpenILS::Application::EResourceLinkClick::Success ) {
        $r->content_type('text/plain');
        $r->print('click recorded');
        return Apache2::Const::OK;
    }
}

1;
