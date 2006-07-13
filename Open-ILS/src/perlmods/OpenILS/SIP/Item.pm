#
#
# A Class for hiding the ILS's concept of the item from the OpenSIP
# system
#

package OpenILS::SIP::Item;

use strict;
use warnings;

use Sys::Syslog qw(syslog);

use OpenILS::SIP::Transaction;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

my %item_db;

sub new {
    my ($class, $item_id) = @_;
    my $type = ref($class) || $class;
    my $self = {};
    bless $self, $type;

	require OpenILS::Utils::CStoreEditor;
	my $e = OpenILS::Utils::CStoreEditor->new;

	if(!UNIVERSAL::can($e, 'search_actor_card')) {
		syslog("LOG_WARNING", "Reloading CStoreEditor...");
		delete $INC{'OpenILS/Utils/CStoreEditor.pm'};
		require OpenILS::Utils::CStoreEditor;
		$e = OpenILS::Utils::CStoreEditor->new;
	}


	 # FLESH ME
	 my $copy = $e->search_asset_copy(
		[
			{ barcode => $item_id },
			{
				flesh => 3,
				flesh_fields => {
					acp => [ 'circ_lib', 'call_number' ],
					acn => [ 'owning_lib', 'record' ],
				}
			}
		]
	);

	if(!@$copy) {
		syslog("LOG_DEBUG", "OpenILS: Item '%s' : not found", $item_id);
		return undef;
    }

	$copy = $$copy[0];

	 # XXX See if i am checked out, if so set $self->{patron} to the user's barcode
	my ($circ) = $U->fetch_open_circulation($copy->id);
	if($circ) {
		my $user = $e->retrieve_actor_user(
			[
				$circ->usr,
				{
					flesh => 1,
					flesh_fields => {
						"au" => [ 'card' ],
					}
				}
			]
		);

		$self->{patron} = $user->card->barcode if $user;
		$self->{patron_object} = $user;
	}

	$self->{id}			= $item_id;
	$self->{copy}		= $copy;
	$self->{volume}	= $copy->call_number;
	$self->{record}	= $copy->call_number->record;
	
	$self->{mods}	= $U->record_to_mvr($self->{record}) if $self->{record}->marc;

    syslog("LOG_DEBUG", "new OpenILS Item('%s'): found with title '%s'",
	   $item_id, $self->title_id);

    return $self;
}

sub magnetic {
    my $self = shift;
	 return 0;
}

sub sip_media_type {
    my $self = shift;
	 return '001';
}

sub sip_item_properties {
    my $self = shift;
	 return "";
}

sub status_update {
    my ($self, $props) = @_;
    my $status = new OpenILS::SIP::Transaction;
    $self->{sip_item_properties} = $props;
    $status->{ok} = 1;
    return $status;
}


sub id {
    my $self = shift;
    return $self->{id};
}

sub title_id {
    my $self = shift;
    return ($self->{mods}) ? $self->{mods}->title : $self->{copy}->dummy_title;
}

sub permanent_location {
    my $self = shift;
	 return $self->{volume}->owning_lib->name;
}

sub current_location {
    my $self = shift;
	 return $self->{copy}->circ_lib->name;
}


# 2 chars 0-99 
sub sip_circulation_status {
    my $self = shift;
	 return '01';
}

sub sip_security_marker {
    return '02';
}

sub sip_fee_type {
    return '01';
}

sub fee {
    my $self = shift;
	 return 0;
}


sub fee_currency {
    my $self = shift;
    'CAD';
}

sub owner {
    my $self = shift;
	 return $self->{volume}->owning_lib->name;
}

sub hold_queue {
    my $self = shift;
	 return [];
}

sub hold_queue_position {
    my ($self, $patron_id) = @_;
	 return 1;
}

sub due_date {
    my $self = shift;
	 return 0;
}

sub recall_date {
    my $self = shift;
    return 0;
}

sub hold_pickup_date {
    my $self = shift;
	 return 0;
}

# message to display on console
sub screen_msg {
    my $self = shift;
    return $self->{screen_msg} || '';
}


# reciept printer
sub print_line {
     my $self = shift;
     return $self->{print_line} || '';
}


# An item is available for a patron if
# 1) It's not checked out and (there's no hold queue OR patron
#    is at the front of the queue)
# OR
# 2) It's checked out to the patron and there's no hold queue
sub available {
     my ($self, $for_patron) = @_;
	  return 1;
}


1;
