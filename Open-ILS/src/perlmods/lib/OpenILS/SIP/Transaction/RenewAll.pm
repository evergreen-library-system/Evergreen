package OpenILS::SIP::Transaction::RenewAll;
use warnings; use strict;

use Sys::Syslog qw(syslog);
use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::SIP::Transaction::Renew;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

our @ISA = qw(OpenILS::SIP::Transaction);

my %fields = (
    renewed => [],
    unrenewed => []
);

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new(@_);

    $self->{_permitted}->{$_} = $fields{$_} for keys %fields;
    @{$self}{keys %fields} = values %fields;
    $self->renewed([]);
    $self->unrenewed([]);

    return bless $self, $class;
}

sub do_renew_all {
    my $self = shift;
    my $sip = shift;

    my $barcodes = $self->patron->charged_items_impl(undef, undef, 1);

    syslog('LOG_INFO', "OILS: RenewalAll for user ".
        $self->patron->{id} ." and items [@$barcodes]");

    for my $barcode (@$barcodes) {
        my $item = $sip->find_item($barcode);

        if ($item and $item->{patron} and $item->{patron} eq $self->patron->{id}) {

            my $renew = OpenILS::SIP::Transaction::Renew->new(authtoken => $self->{authtoken});
            $renew->patron($self->patron);
            $renew->item($item);
            $renew->do_renew; # renew this single item

            if ($renew->renewal_ok) {
                push(@{$self->renewed}, $barcode);
               
            } else {
                push(@{$self->unrenewed}, $barcode);
            }

        } else {
            syslog('LOG_INFO', "OILS: RenewalAll item " . $item->{id} . 
                " is not checked out to user " . $self->patron->{id} . 
                ". It's checked out to user " . $item->{patron});

            push(@{$self->unrenewed}, $barcode);
        }
    }

    syslog('LOG_INFO', "OILS: RenewalAll ".
        "ok=[@{$self->renewed}]; not-ok=[@{$self->unrenewed}]");

    $self->ok(1);
    return $self;
}

