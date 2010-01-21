package OpenILS::Application::Acq::EDI;
use base qw/OpenILS::Application/;

use strict; use warnings;

use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Acq::EDI::Translator;

# use OpenILS::Event;
use OpenSRF::Utils::Logger qw(:logger);
# use OpenSRF::Utils::JSON;
# use OpenILS::Utils::Fieldmapper;
# use OpenILS::Utils::CStoreEditor q/:funcs/;
# use OpenILS::Const qw/:const/;
# use OpenILS::Application::AppUtils;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    # $self->{args} = {};
    return $self;
}

our $translator;

sub translator {
    return $translator ||= OpenILS::Application::Acq::EDI::Translator->new(@_);
}

__PACKAGE__->register_method(
	method    => 'retrieve',
	api_name  => 'open-ils.acq.edi.retrieve',
	signature => {
        desc  => 'Fetch incoming message(s) from EDI accounts.  ' .
                 'Optional arguments to restrict to one vendor and/or a max number of messages.  ' .
                 'Note that messages are not parsed or processed here, just fetched and translated.',
        param => [
            {desc => 'Authentication token',        type => 'string'},
            {desc => 'Vendor ID (undef for "all")', type => 'number'},
            {desc => 'Max Messages Retrieved',      type => 'number'}
        ],
        return => {
            desc => 'List of new message IDs (empty if none)',
            type => 'array'
        }
    }
);

sub retrieve {
    my ($self, $conn, $auth, $vendor_id, $max) = @_;

    my @return = ();
    my $e = new_editor(xact=>1, authtoken=>$auth);
    unless ($e->checkauth) {
        $logger->warn("checkauth failed for authtoken '$auth'");
        return @return;
    }

    my $criteria = {};
    $criteria->{vendor_id} = $vendor_id if $vendor_id;
    my $set = $e->search_acq_edi_account(
        $criteria, {
            flesh => 1,
            flesh_fields => {
            }
        }
    ) or return $e->die_event;

    my $tran = translator();
    foreach my $account (@$set) {
        $logger->warn("EDI check for " . $account->host);
# foreach message {
#       my $incoming = $e->create_acq_edi_message;
#       $incoming->edi($content);
#       $incoming->edi_account($account->id);
#       my $json = $tran->edi2json;
#       unless ($json) {
#           $logger->error("EDI Translator failed on $incoming->id");
#           next;
#       }
#       $incoming->json($json);
#       $e->commit;
#       delete remote copies of saved message (?)
#       push @return, $incoming->id;
# }
    }
    # return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $li->purchase_order->ordering_agency);
    # $e->commit;
    return @return;
}

sub record_activity {
    my $self = shift;
    my $account = shift or return;
}

sub retrieve_one {
    my $self = shift;
    my $account = shift or return;

}

1;

