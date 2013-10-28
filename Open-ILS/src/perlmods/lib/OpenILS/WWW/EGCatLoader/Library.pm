package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';
my $library_cache;

# context additions: 
#   library : aou object
#   parent: aou object
sub load_library {
    my $self = shift;
    my %kwargs = @_;
    my $ctx = $self->ctx;
    $ctx->{page} = 'library';  

    $self->timelog("load_library() began");

    my $lib_id = $ctx->{page_args}->[0];
    $lib_id = $self->_resolve_org_id_or_shortname($lib_id);

    return Apache2::Const::HTTP_BAD_REQUEST unless $lib_id;

    my $aou = $ctx->{get_aou}->($lib_id);
    my $sname = $aou->parent_ou;

    $ctx->{library} = $aou;
    if ($aou->parent_ou) {
        $ctx->{parent} = $ctx->{get_aou}->($aou->parent_ou);
    }

    $self->timelog("got basic lib info");

    # Get mailing address from the cache
    $library_cache ||= OpenSRF::Utils::Cache->new('global');
    my $address_cache_key = "TPAC_aou_address_cache_$lib_id";
    my $address = OpenSRF::Utils::JSON->JSON2perl($library_cache->get_cache($address_cache_key));

    if ($address) {
        $ctx->{mailing_address} = $address;
    } elsif (!$address && $aou->mailing_address) {
        # We didn't get cached hours, so hit the database
        my $session = OpenSRF::AppSession->create("open-ils.actor");
        $ctx->{mailing_address} =
            $session->request('open-ils.actor.org_unit.address.retrieve',
            $aou->mailing_address)->gather(1);
        $library_cache->put_cache($address_cache_key, OpenSRF::Utils::JSON->perl2JSON($ctx->{mailing_address}), 360);
    }

    # Get current hours of operation
    my $hours_cache_key = "TPAC_aouhoo_cache_$lib_id";
    my $hours = OpenSRF::Utils::JSON->JSON2perl($library_cache->get_cache($hours_cache_key));

    # If we don't have cached hours, try the database
    if (!$hours) {
        $hours = $self->editor->retrieve_actor_org_unit_hours_of_operation($lib_id);
        # If we got hours from the database, cache them
        if ($hours) {
            $library_cache->put_cache($hours_cache_key, OpenSRF::Utils::JSON->perl2JSON($hours), 360);
        }
    }

    # After all that, if we have hours, pass them to the context object
    if ($hours) {
        $ctx->{hours} = $hours;
    }

    return Apache2::Const::OK;
}

1;
