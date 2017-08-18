package OpenILS::Application::Trigger::Validator::Acq::PurchaseOrderEDIRequired;
use strict; use warnings;
# use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/ new_editor /;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

sub handler {
    my $self = shift;
    my $env  = shift;
    my $po   = $env->{target};

    my $provider = 
        ref($po->provider) ? 
            $po->provider : 
            new_editor->retrieve_acq_provider($po->provider);

    return 1 if 
        ($po->state eq 'on-order' || $po->state eq 'retry')
        and $provider
        and $provider->edi_default
        and $U->is_true($provider->active)
        and !$U->is_true($provider->edi_default->use_attrs);

    return 0;
}

1;
