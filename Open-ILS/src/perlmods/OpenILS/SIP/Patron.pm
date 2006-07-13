#
# 
# A Class for hiding the ILS's concept of the patron from the OpenSIP
# system
#

package OpenILS::SIP::Patron;

use strict;
use warnings;
use Exporter;

use Sys::Syslog qw(syslog);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);

use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

our (@ISA, @EXPORT_OK);

@ISA = qw(Exporter);

@EXPORT_OK = qw(invalid_patron);

sub new {
    my ($class, $patron_id) = @_;
    my $type = ref($class) || $class;
    my $self = {};

	syslog("LOG_DEBUG", "new OpenILS Patron(%s): searching...", $patron_id);

	require OpenILS::Utils::CStoreEditor;
	my $e = OpenILS::Utils::CStoreEditor->new;

	if(!UNIVERSAL::can($e, 'search_actor_card')) {
		syslog("LOG_WARNING", "Reloading CStoreEditor...");
		delete $INC{'OpenILS/Utils/CStoreEditor.pm'};
		require OpenILS::Utils::CStoreEditor;
		$e = OpenILS::Utils::CStoreEditor->new;
	}


	 my $c = $e->search_actor_card({barcode => $patron_id}, {idlist=>1});
	 my $user;

	 if( @$c ) {

		$user = $e->search_actor_user(
			[
				{ card => $$c[0] },
				{
					flesh => 1,
					flesh_fields => {
						"au" => [
							#"cards",
							"card",
							"standing_penalties",
							"addresses",
							"billing_address",
							"mailing_address",
							#"stat_cat_entries",
							'profile',
						]
					}
				}
			]
		);

		$user = (@$user) ? $$user[0] : undef;
	 }

	 if(!$user) {
		syslog("LOG_WARNING", "Unable to find patron %s", $patron_id);
		return undef;
	 }

	$self->{user}		= $user;
	$self->{id}			= $patron_id;
	$self->{editor}	= $e;

	syslog("LOG_DEBUG", "new OpenILS Patron(%s): found patron '%s'", $patron_id);

	bless $self, $type;
	return $self;
}

sub id {
    my $self = shift;
    return $self->{id};
}

sub name {
    my $self = shift;
	 my $u = $self->{user};
	 return $u->first_given_name . ' ' . 
		$u->second_given_name . ' ' . $u->family_name;
}

sub __addr_string {
	my $addr = shift;
	return "" unless $addr;
	return $addr->street1 .' '. 
		$addr->street2 .' '.
		$addr->city .' '.
		$addr->county .' '.
		$addr->state .' '.
		$addr->country .' '.
		$addr->post_code;
}

sub address {
	my $self = shift;
	my $u = $self->{user};
	my $addr = $u->billing_address;
	my $str = __addr_string($addr);
	my $maddr = $u->mailing_address;
	$str .= "\n" . __addr_string($maddr) 
		if $maddr and $maddr->id ne $addr->id;
	return $str;
}

sub email_addr {
    my $self = shift;
	return $self->{user}->email;
}

sub home_phone {
    my $self = shift;
	return $self->{user}->day_phone;
}

sub sip_birthdate {
    my $self = shift;
	return $self->{user}->dob;
}

sub ptype {
    my $self = shift;
	return $self->{user}->profile->name;
}

sub language {
    my $self = shift;
    return '000'; # Unspecified
}

# How much more detail do we need to check here?
sub charge_ok {
    my $self = shift;
	 my $u = $self->{user};
	 return ($u->barred ne 't') and ($u->card->active ne 'f');
}

# How much more detail do we need to check here?
sub renew_ok {
    my $self = shift;
	 my $u = $self->{user};
	 return ($u->barred ne 'f') and ($u->card->active ne 'f');
}

sub recall_ok {
    my $self = shift;
    return 0;
}

sub hold_ok {
    my $self = shift;
    return 0;
}

# return true if the card provided is marked as lost
sub card_lost {
    my $self = shift;
    return 0;
}

sub recall_overdue {
    my $self = shift;
    return 0;
}


sub check_password {
	my ($self, $pwd) = @_;
	return md5_hex($pwd) eq $self->{user}->passwd;
}


sub currency {
	my $self = shift;
	return 'usd';
}


sub fee_amount {
	my $self = shift;
	return 0;
}

sub screen_msg {
    my $self = shift;
	return '';
}

sub print_line {
    my $self = shift;
	return '';
}

sub too_many_charged {
    my $self = shift;
	return 0;
}

sub too_many_overdue {
	my $self = shift;
	if( $self->{user}->standing_penalties ) {
		return grep { $_->penalty_type eq 'PATRON_EXCEEDS_OVERDUE_COUNT' } 
			@{$self->{user}->standing_penalties};
	}
	return 0;
}

# not completely sure what this means
sub too_many_renewal {
    my $self = shift;
	return 0;
}

# not relevant, handled by fines/fees
sub too_many_claim_return {
    my $self = shift;
	return 0;
}

# not relevant, handled by fines/fees
sub too_many_lost {
    my $self = shift;
	return 0;
}

sub excessive_fines {
    my $self = shift;
	if( $self->{user}->standing_penalties ) {
		return grep { $_->penalty_type eq 'PATRON_EXCEEDS_FINES' } 
			@{$self->{user}->standing_penalties};
	}
	return 0;
}


# Until someone suggests otherwise, fees and fines are the same

sub excessive_fees {
	my $self = shift;
	if( $self->{user}->standing_penalties ) {
		return grep { $_->penalty_type eq 'PATRON_EXCEEDS_FINES' } 
			@{$self->{user}->standing_penalties};
	}
	return 0;
}

# not relevant, handled by fines/fees
sub too_many_billed {
    my $self = shift;
	return 0;
}



#
# List of outstanding holds placed
#
sub hold_items {
    my ($self, $start, $end) = @_;

	 my $holds = $self->{editor}->search_action_hold_request(
		{ usr => $self->{user}->id, fulfillment_time => undef }
	 );

	my @holds;
	push( @holds, $self->__hold_to_title($_) ) for @$holds;

	return (defined $start and defined $end) ? 
		[ $holds[($start-1)..($end-1)] ] : 
		\@holds;
}

sub __hold_to_title {
	my $self = shift;
	my $hold = shift;
	my $e = $self->{editor};

	my( $id, $mods, $title, $volume, $copy );

	if( $hold->hold_type eq 'C' ) {
		$copy = $e->retrieve_asset_copy($hold->target);
	}

	if( $copy || $hold->hold_type eq 'V' ) {
		return $copy->dummy_title if $copy and $copy->call_number == -1;
		$id = ($copy) ? $copy->call_number : $hold->target;
		$volume = $e->retrieve_asset_call_number($id);
	}

	if( $volume || $hold->hold_type eq 'T' ) {
		$id = ($volume) ? $volume->record : $hold->target;
		$mods = $U->simplereq(
			'open-ils.search',
			'open-ils.search.biblio.record.mods_slim.retrieve', $id );
	}

	if( $hold->hold_type eq 'M' ) {
		$mods = $U->simplereq(
			'open-ils.search',
			'open-ils.search.biblio.metarecord.mods_slim.retrieve', $hold->target);
	}


	return ($mods) ? $mods->title : "";
}

#
# remove the hold on item item_id from my hold queue.
# return true if I was holding the item, false otherwise.
# 
sub drop_hold {
    my ($self, $item_id) = @_;
    return 0;
}

sub overdue_items {
    my ($self, $start, $end) = @_;
	 my @overdues;

	return (defined $start and defined $end) ? 
		[ $overdues[($start-1)..($end-1)] ] : 
		\@overdues;
}

sub charged_items {
	my ($self, $start, $end) = shift;
	my @charges;

	return (defined $start and defined $end) ? 
		[ $charges[($start-1)..($end-1)] ] : 
		\@charges;
}

sub fine_items {
	my ($self, $start, $end) = @_;
	my @fines;
	return (defined $start and defined $end) ? 
		[ $fines[($start-1)..($end-1)] ] : \@fines;
}

# not currently supported
sub recall_items {
    my ($self, $start, $end) = @_;
	 return [];
}

sub unavail_holds {
	my ($self, $start, $end) = @_;
	my @holds;
	return (defined $start and defined $end) ? 
		[ $holds[($start-1)..($end-1)] ] : \@holds;
}

sub block {
    my ($self, $card_retained, $blocked_card_msg) = @_;
	 # Mark the card as inactive, set patron alert
    return $self;
}

# Testing purposes only
sub enable {
    my $self = shift;
	 # Un-mark card as inactive, grep out the patron alert
    $self->{screen_msg} = "All privileges restored.";
    return $self;
}

#
# Messages
#

sub invalid_patron {
    return "Please contact library staff";
}

sub charge_denied {
    return "Please contact library staff";
}

1;
