package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::Utils::JSON;
use Data::Dumper;
$Data::Dumper::Indent = 0;
use DateTime;
my $U = 'OpenILS::Application::AppUtils';

sub load_sms_cn {
    my $self = shift;
    my $ctx = $self->ctx;
    my $gos = $ctx->{get_org_setting};
    my $e = $self->editor;
    my $cgi = $self->cgi;

    my $org_unit = $cgi->param('loc') || $ctx->{aou_tree}->()->id;

    $self->_load_user_with_prefs() if($e->checkauth);

    $ctx->{page} = 'sms_cn';
    $ctx->{sms_carrier} = $cgi->param('sms_carrier');
    $ctx->{sms_notify} = $cgi->param('sms_notify');
    $ctx->{copy_id} = $cgi->param('copy_id');
    $ctx->{query} = $cgi->param('query');
    $ctx->{origin} = $cgi->param('origin') || $cgi->referer;

    my $acn_results = $e->json_query({
        select => {
            acp => ['call_number']
        },
        from => 'acp',
        where => {id => $ctx->{copy_id}}
    });

    my $acn_ids = [map { $_->{call_number} } @$acn_results];
    $ctx->{acn_ids} = $acn_ids;

    my $resp = $U->simplereq('open-ils.cat', 'open-ils.cat.acn.send_sms_text',
        $e->authtoken, $org_unit,
        $ctx->{sms_carrier}, $ctx->{sms_notify},
        $acn_ids
    );

    $ctx->{event} = $resp;

    $ctx->{orig_params} = $cgi->Vars;

    return Apache2::Const::OK;
}


