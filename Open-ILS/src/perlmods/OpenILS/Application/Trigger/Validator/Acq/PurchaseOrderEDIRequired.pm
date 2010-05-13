package OpenILS::Application::Trigger::Validator::Acq::PurchaseOrderEDIRequired;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

sub handler {
    my $self = shift;
    my $env = shift;
    my $po = $env->{target};

    my $provider = 
        ref($po->provider) ? 
            $po->provider : 
            $self->editor->retrieve_acq_provider($po->provider);

    return 1 if 
        $po->state eq 'on-order' and 
        $provider->edi_default and 
        $U->is_true($provider->active);

    return 0;
}

1;
