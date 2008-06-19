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

use OpenILS::SIP;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Actor;
use OpenSRF::Utils qw/:datetime/;
use DateTime::Format::ISO8601;
my $U = 'OpenILS::Application::AppUtils';

our (@ISA, @EXPORT_OK);

@ISA = qw(Exporter);

@EXPORT_OK = qw(invalid_patron);

my $INET_PRIVS;

sub new {
    my ($class, $patron_id) = @_;
    my $type = ref($class) || $class;
    my $self = {};

	syslog("LOG_DEBUG", "OILS: new OpenILS Patron(%s): searching...", $patron_id);

	my $e = OpenILS::SIP->editor();

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
		syslog("LOG_WARNING", "OILS: Unable to find patron %s", $patron_id);
		return undef;
	 }

	$self->{user}		= $user;
	$self->{id}			= $patron_id;
	$self->{editor}	= $e;

	syslog("LOG_DEBUG", "OILS: new OpenILS Patron(%s): found patron : barred=%s, card:active=%s", 
		$patron_id, $self->{user}->barred, $self->{user}->card->active );


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

sub home_library {
    my $self = shift;
    my $lib = $self->{editor}->retrieve_actor_org_unit($self->{user}->home_ou)->shortname;
	syslog('LOG_DEBUG', "OILS: Patron home library is $lib");
    return $lib;
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
	$addr = $u->mailing_address unless $addr;
	my $str = __addr_string($addr);
	syslog('LOG_DEBUG', "OILS: Patron address: $str");
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
	my $dob = OpenILS::SIP->format_date($self->{user}->dob);
	syslog('LOG_DEBUG', "OILS: Patron DOB = $dob");
	return $dob;
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
	 return (($u->barred eq 'f') and ($u->card->active eq 't'));
}

# How much more detail do we need to check here?
sub renew_ok {
    my $self = shift;
	 return $self->charge_ok;
}

sub recall_ok {
    my $self = shift;
    return 0;
}

sub hold_ok {
    my $self = shift;
	 return $self->charge_ok;
}

# return true if the card provided is marked as lost
sub card_lost {
    my $self = shift;
	 return $self->{user}->card->active eq 'f';
}

sub recall_overdue {
    my $self = shift;
    return 0;
}


sub check_password {
	my ($self, $pwd) = @_;
	syslog('LOG_DEBUG', 'OILS: Patron->check_password()');
	return md5_hex($pwd) eq $self->{user}->passwd;
}


sub currency {
	my $self = shift;
	syslog('LOG_DEBUG', 'OILS: Patron->currency()');
	return 'USD';
}

sub fee_amount {
	my $self = shift;
	syslog('LOG_DEBUG', 'OILS: Patron->fee_amount()');

	my $ses = $U->start_db_session();
	my $summary = $ses->request(
		'open-ils.storage.money.open_user_summary.search', $self->{user}->id )->gather(1);
	$U->rollback_db_session($ses);

	my $total = $summary->balance_owed;
	syslog('LOG_INFO', "User ".$self->{id} .':'.$self->{user}->id." has a fee amount of \$$total");
	return $total;
}

sub screen_msg {
	my $self = shift;
	my $u = $self->{user};
	return 'barred' if $u->barred eq 't';

	my $b = 'blocked';

	return $b if $u->active eq 'f';
	return $b if $u->card->active eq 'f';

	if( $u->standing_penalties ) {
		return $b if 
			grep { $_->penalty_type eq 'PATRON_EXCEEDS_OVERDUE_COUNT' } 
				@{$u->standing_penalties};

		return $b if 
			grep { $_->penalty_type eq 'PATRON_EXCEEDS_FINES' } 
				@{$u->standing_penalties};
	}

	my $expire = DateTime::Format::ISO8601->new->parse_datetime(
		clense_ISO8601($u->expire_date));

	return $b if CORE::time > $expire->epoch;

	return 'OK';
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
	syslog('LOG_DEBUG', 'OILS: Patron->excessive_fines()');
	if( $self->{user}->standing_penalties ) {
		return grep { $_->penalty_type eq 'PATRON_EXCEEDS_FINES' } 
			@{$self->{user}->standing_penalties};
	}
	return 0;
}


# Until someone suggests otherwise, fees and fines are the same

sub excessive_fees {
	my $self = shift;
	syslog('LOG_DEBUG', 'OILS: Patron->excessive_fees()');
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
		{ usr => $self->{user}->id, fulfillment_time => undef, cancel_time => undef }
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

	return __copy_to_title($e, 
		$e->retrieve_asset_copy($hold->target)) 
		if $hold->hold_type eq 'C';

	return __volume_to_title($e, 
		$e->retrieve_asset_call_number($hold->target))
		if $hold->hold_type eq 'V';

	return __record_to_title(
		$e, $hold->target) if $hold->hold_type eq 'T';

	return __metarecord_to_title(
		$e, $hold->target) if $hold->hold_type eq 'M';
}

sub __copy_to_title {
	my( $e, $copy ) = @_;
	#syslog('LOG_DEBUG', "OILS: copy_to_title(%s)", $copy->id);
	return $copy->dummy_title if $copy->call_number == -1;	

	my $vol = (ref $copy->call_number) ?
		$copy->call_number :
		$e->retrieve_asset_call_number($copy->call_number);

	return __volume_to_title($e, $vol);
}


sub __volume_to_title {
	my( $e, $volume ) = @_;
	#syslog('LOG_DEBUG', "OILS: volume_to_title(%s)", $volume->id);
	return __record_to_title($e, $volume->record);
}


sub __record_to_title {
	my( $e, $title_id ) = @_;
	#syslog('LOG_DEBUG', "OILS: record_to_title($title_id)");
	my $mods = $U->simplereq(
		'open-ils.search',
		'open-ils.search.biblio.record.mods_slim.retrieve', $title_id );
	return ($mods) ? $mods->title : "";
}

sub __metarecord_to_title {
	my( $e, $m_id ) = @_;
	#syslog('LOG_DEBUG', "OILS: metarecord_to_title($m_id)");
	my $mods = $U->simplereq(
		'open-ils.search',
		'open-ils.search.biblio.metarecord.mods_slim.retrieve', $m_id);
	return ($U->event_code($mods)) ? "<unknown>" : $mods->title;
}


#
# remove the hold on item item_id from my hold queue.
# return true if I was holding the item, false otherwise.
# 
sub drop_hold {
    my ($self, $item_id) = @_;
    return 0;
}

sub __patron_items_info {
	my $self = shift;
	return if $self->{items_info};
	$self->{item_info} = 
		OpenILS::Application::Actor::_checked_out(
			0, $self->{editor}, $self->{user}->id);;
}

sub overdue_items {
	my ($self, $start, $end) = @_;

	$self->__patron_items_info();
	my @overdues = @{$self->{item_info}->{overdue}};
	#$overdues[$_] = __circ_to_title($self->{editor}, $overdues[$_]) for @overdues;

	my @o;
	syslog('LOG_DEBUG', "OILS: overdue_items() fleshing circs @overdues");
	
	
	my @return_datatype = grep { $_->{name} eq 'msg64_summary_datatype' } @{$self->{config}->{implementation_config}->{options}->{option}};
	
	for my $circid (@overdues) {
		next unless $circid;
		if(@return_datatype and $return_datatype[0]->{value} eq 'barcode') {
			push( @o, __circ_to_barcode($self->{editor}, $circid));
		} else {
			push( @o, __circ_to_title($self->{editor}, $circid));
		}
	}
	@overdues = @o;

	return (defined $start and defined $end) ? 
		[ $overdues[($start-1)..($end-1)] ] : \@overdues;
}

sub __circ_to_barcode {
	my ($e, $circ) = @_;
	return unless $circ;
	$circ = $e->retrieve_action_circulation($circ);
	my $copy = $e->retrieve_asset_copy($circ->target_copy);
	return $copy->barcode;
}

sub __circ_to_title {
	my( $e, $circ ) = @_;
	return unless $circ;
	$circ = $e->retrieve_action_circulation($circ);
	return __copy_to_title( $e, 
		$e->retrieve_asset_copy($circ->target_copy) );
}

sub charged_items {
	my ($self, $start, $end) = shift;

	$self->__patron_items_info();

	my @charges = (
		@{$self->{item_info}->{out}},
		@{$self->{item_info}->{overdue}}
		);

	#$charges[$_] = __circ_to_title($self->{editor}, $charges[$_]) for @charges;

	my @c;
	syslog('LOG_DEBUG', "OILS: charged_items() fleshing circs @charges");

	my @return_datatype = grep { $_->{name} eq 'msg64_summary_datatype' } @{$self->{config}->{implementation_config}->{options}->{option}};

	for my $circid (@charges) {
		next unless $circid;
		if(@return_datatype and $return_datatype[0]->{value} eq 'barcode') {
			push( @c, __circ_to_barcode($self->{editor}, $circid));
		} else {
			push( @c, __circ_to_title($self->{editor}, $circid));
		}
	}

	@charges = @c;

	return (defined $start and defined $end) ? 
		[ $charges[($start-1)..($end-1)] ] : 
		\@charges;
}

sub fine_items {
	my ($self, $start, $end) = @_;
	my @fines;
	syslog('LOG_DEBUG', 'OILS: Patron->fine_items()');
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

	my $u = $self->{user};
	my $e = $self->{editor} = OpenILS::SIP->reset_editor();

	syslog('LOG_INFO', "OILS: Blocking user %s", $u->card->barcode );

	return $self if $u->card->active eq 'f';

	$u->card->active('f');
	if( ! $e->update_actor_card($u->card) ) {
		syslog('LOG_ERR', "OILS: Block card update failed: %s", $e->event->{textcode});
		$e->xact_rollback;
		return $self;
	}

	# retrieve the un-fleshed user object for update
	$u = $e->retrieve_actor_user($u->id);
	my $note = $u->alert_message || "";
	$note = "CARD BLOCKED BY SELF-CHECK MACHINE\n$note"; # XXX Config option

	$u->alert_message($note);

	if( ! $e->update_actor_user($u) ) {
		syslog('LOG_ERR', "OILS: Block: patron alert update failed: %s", $e->event->{textcode});
		$e->xact_rollback;
		return $self;
	}

	# stay in synch
	$self->{user}->alert_message( $note );

	$e->commit; # commits and resets
	$self->{editor} = OpenILS::SIP->reset_editor();
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

sub inet_privileges {
	my( $self ) = @_;
	my $e = OpenILS::SIP->editor();
	$INET_PRIVS = $e->retrieve_all_config_net_access_level() unless $INET_PRIVS;
	my ($level) = grep { $_->id eq $self->{user}->net_access_level } @$INET_PRIVS;
	my $name = $level->name;
	syslog('LOG_DEBUG', "OILS: Patron inet_privs = $name");
	return $name;
}


1;
