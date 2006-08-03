#
#
# A Class for hiding the ILS's concept of the item from the OpenSIP
# system
#

package OpenILS::SIP::Item;
use strict; use warnings;

use Sys::Syslog qw(syslog);

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

my %item_db;

sub new {
    my ($class, $item_id) = @_;
    my $type = ref($class) || $class;
    my $self = bless( {}, $type );

	syslog('LOG_DEBUG', "Loading item $item_id...");
	return undef unless $item_id;

	my $e = OpenILS::SIP->editor();

	 # FLESH ME
	my $copy = $e->search_asset_copy(
		[
			{ barcode => $item_id },
			{
				flesh => 3,
				flesh_fields => {
					acp => [ 'circ_lib', 'call_number', 'status' ],
					acn => [ 'owning_lib', 'record' ],
				}
			}
		]
	);

	$copy = $$copy[0];

	if(!$copy) {
		syslog("LOG_DEBUG", "OpenILS: Item '%s' : not found", $item_id);
		return undef;
	}

	my ($circ) = $U->fetch_open_circulation($copy->id);
	if($circ) {
		# if i am checked out, set $self->{patron} to the user's barcode
		my $user = $e->retrieve_actor_user(
			[
				$circ->usr,
				{ flesh => 1, flesh_fields => { "au" => [ 'card' ] } }
			]
		);

		my $bc = ($user) ? $user->card->barcode : "";
		$self->{patron} = $bc;
		$self->{patron_object} = $user;

		syslog('LOG_DEBUG', "Open circulation exists on $item_id : user = $bc");
	}

	$self->{id}			= $item_id;
	$self->{copy}		= $copy;
	$self->{volume}	= $copy->call_number;
	$self->{record}	= $copy->call_number->record;
	$self->{mods}		= $U->record_to_mvr($self->{record}) if $self->{record}->marc;

	syslog("LOG_DEBUG", "Item('$item_id'): found with title '%s'", $self->title_id);

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
    my $status = OpenILS::SIP::Transaction->new;
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
# 01 Other
# 02 On order
# 03 Available
# 04 Charged
# 05 Charged; not to be recalled until earliest recall date
# 06 In process
# 07 Recalled
# 08 Waiting on hold shelf
# 09 Waiting to be re-shelved
# 10 In transit between library locations
# 11 Claimed returned
# 12 Lost
# 13 Missing 
sub sip_circulation_status {
	my $self = shift;
	return '03' if $self->{copy}->status->name =~ /available/i;
	return '04' if $self->{copy}->status->name =~ /checked out/i;
	return '06' if $self->{copy}->status->name =~ /in process/i;
	return '08' if $self->{copy}->status->name =~ /on holds shelf/i;
	return '09' if $self->{copy}->status->name =~ /reshelving/i;
	return '10' if $self->{copy}->status->name =~ /in transit/i;
	return '12' if $self->{copy}->status->name =~ /lost/i;
	return 01;
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
    'USD';
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
	my $e = OpenILS::SIP->editor();

	my $circ = $e->search_action_circulation(
		{ target_copy => $self->{copy}->id, stop_fines => undef } )->[0];

	if(!$circ) {
		# if not, lets look for other circs we can check in
		$circ = $e->search_action_circulation(
			{ 
				target_copy => $self->{copy}->id, 
				xact_finish => undef,
				stop_fines	=> [ 'CLAIMSRETURNED', 'LOST', 'LONGOVERDUE' ]
			} )->[0];
	}

	return $circ->due_date if $circ;
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
