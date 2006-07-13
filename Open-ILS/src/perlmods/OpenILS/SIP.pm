#
# ILS.pm: Test ILS interface module
#

package OpenILS::SIP;
use warnings; use strict;

use Sys::Syslog qw(syslog);

use OpenILS::SIP::Item;
use OpenILS::SIP::Patron;
use OpenILS::SIP::Transaction;
use OpenILS::SIP::Transaction::Checkout;
use OpenILS::SIP::Transaction::Checkin;
use OpenILS::SIP::Transaction::FeePayment;
use OpenILS::SIP::Transaction::Hold;
use OpenILS::SIP::Transaction::Renew;
use OpenILS::SIP::Transaction::RenewAll;


use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;

use Digest::MD5 qw(md5_hex);

my $U = 'OpenILS::Application::AppUtils';

# PUT ME IN THE CONFIG XXX
my %supports = (
		'magnetic media' => 1,
		'security inhibit' => 0,
		'offline operation' => 0
		);


sub new {
	my ($class, $institution, $login) = @_;
	my $type = ref($class) || $class;
	my $self = {};

	syslog("LOG_DEBUG", "new ILS '%s'", $institution->{id});
	$self->{institution} = $institution;

	my $config = $institution->{implementation_config}->{bootstrap};

	syslog('LOG_DEBUG', "loading bootstrap config: $config");
	
	local $/ = "\n";
	OpenSRF::System->bootstrap_client(config_file => $config);
	syslog('LOG_DEBUG', "bootstrap loaded..");

	$self->{osrf_config} = OpenSRF::Utils::SettingsClient->new;

	Fieldmapper->import($self->{osrf_config}->config_value('IDL'));

	bless( $self, $type );

	return undef unless 
		$self->login( $login->{id}, $login->{password} );

	return $self;
}

sub login {
	my( $self, $username, $password ) = @_;
	syslog('LOG_DEBUG', "OpenILS: Logging in with username $username");

	my $seed = $U->simplereq( 
		'open-ils.auth',
		'open-ils.auth.authenticate.init', $username );

	my $response = $U->simplereq(
		'open-ils.auth', 
		'open-ils.auth.authenticate.complete', 
		{	
			username => $username, 
			password => md5_hex($seed . md5_hex($password)), 
			type		=> 'opac',
		}
	);

	my $key;
	if( ref($response) eq 'HASH' and $response->{payload} 
		and $key = $response->{payload}->{authtoken} ) {
		syslog('LOG_INFO', "OpenILS: Login succeeded for $username : authkey = $key");

	} else {
		syslog('LOG_WARN', "OpenILS: Login failed for $username");
	}

	return $self->{authtoken} = $key;
}


sub find_patron {
	my $self = shift;
	return OpenILS::SIP::Patron->new(@_);
}


sub find_item {
	my $self = shift;
	return OpenILS::SIP::Item->new(@_);
}


sub institution {
    my $self = shift;

    return $self->{institution}->{id};
}


# XXX Get me from the config?
sub supports {
    my ($self, $op) = @_;
    return exists($supports{$op}) ? $supports{$op} : 0;
}

sub check_inst_id {
    my ($self, $id, $whence) = @_;

    if ($id ne $self->{institution}->{id}) {
	syslog("LOG_WARNING", "%s: received institution '%s', expected '%s'",
	       $whence, $id, $self->{institution}->{id});
    }
}




# XXX by default, these should come from the config
sub checkout_ok {
    return 1;
}

sub checkin_ok {
    return 0;
}

sub status_update_ok {
    return 1;
}

sub offline_ok {
    return 0;
}


##
## Checkout(patron_id, item_id, sc_renew):
##    patron_id & item_id are the identifiers send by the terminal
##    sc_renew is the renewal policy configured on the terminal
## returns a status opject that can be queried for the various bits
## of information that the protocol (SIP or NCIP) needs to generate
## the response.
##

sub checkout {
	my ($self, $patron_id, $item_id, $sc_renew) = @_;
	
	syslog('LOG_DEBUG', "OpenILS::Checkout attempt: patron=$patron_id, item=$item_id");
	
	my $xact		= OpenILS::SIP::Transaction::Checkout->new( authtoken => $self->{authtoken} );
	my $patron	= OpenILS::SIP::Patron->new($patron_id);
	my $item		= OpenILS::SIP::Item->new($item_id);
	
	$xact->patron($patron);
	$xact->item($item);

	if (!$patron) {
		$xact->screen_msg("Invalid Patron");
		return $xact;
	}

	if (!$patron->charge_ok) {
		$xact->screen_msg("Patron Blocked");
		return $xact;
	}

	if( !$item ) {
		$xact->screen_msg("Invalid Item");
		return $xact;
	}

	syslog('LOG_DEBUG', "OpenILS::Checkout data loaded OK, checking out...");
	$xact->do_checkout();

	if ($item->{patron} && ($item->{patron} ne $patron_id)) {
		# I can't deal with this right now
		# XXX check in then check out?
		$xact->screen_msg("Item checked out to another patron");
		$xact->ok(0);
	} 

	$xact->desensitize(!$item->magnetic);

	if( $xact->ok ) {

		$xact->editor->commit;
		syslog("LOG_DEBUG", "OpenILS::Checkout: " .
			"patron %s checke out %s succeeded", $patron_id, $item_id);

	} else {

		$xact->editor->xact_rollback;
		syslog("LOG_DEBUG", "OpenILS::Checkout: " .
			"patron %s checke out %s FAILED, rolling back xact...", $patron_id, $item_id);
	}

	return $xact;
}


sub checkin {
	my ($self, $item_id, $trans_date, $return_date,
	$current_loc, $item_props, $cancel) = @_;

	syslog('LOG_DEBUG', "OpenILS::Checkin on item=$item_id");
	
	my $patron;
	my $xact		= OpenILS::SIP::Transaction::Checkin->new(authtoken => $self->{authtoken});
	my $item		= OpenILS::SIP::Item->new($item_id);

	$xact->item($item);

	$xact->do_checkin( $trans_date, $return_date, $current_loc, $item_props );
	
	if ($xact->ok) {

		$xact->patron($patron = OpenILS::SIP::Patron->new($item->{patron}));
		delete $item->{patron};
		delete $item->{due_date};
		syslog('LOG_INFO', "OpenILS: Checkin succeeded");
		$xact->editor->commit;

	} else {

		$xact->editor->xact_rollback;
		syslog('LOG_WARNING', "OpenILS: Checkin failed");
	}
	# END TRANSACTION

	return $xact;
}




## If the ILS caches patron information, this lets it free
## it up
#sub end_patron_session {
#    my ($self, $patron_id) = @_;
#
#    # success?, screen_msg, print_line
#    return (1, 'Thank you for using OpenILS!', '');
#}
#
#sub pay_fee {
#    my ($self, $patron_id, $patron_pwd, $fee_amt, $fee_type,
#	$pay_type, $fee_id, $trans_id, $currency) = @_;
#    my $trans;
#    my $patron;
#
#    $trans = new ILS::Transaction::FeePayment;
#
#    $patron = new ILS::Patron $patron_id;
#
#    $trans->transaction_id($trans_id);
#    $trans->patron($patron);
#    $trans->ok(1);
#
#    return $trans;
#}
#
#sub add_hold {
#    my ($self, $patron_id, $patron_pwd, $item_id, $title_id,
#	$expiry_date, $pickup_location, $hold_type, $fee_ack) = @_;
#    my ($patron, $item);
#    my $hold;
#    my $trans;
#
#
#    $trans = new ILS::Transaction::Hold;
#
#    # BEGIN TRANSACTION
#    $patron = new ILS::Patron $patron_id;
#    if (!$patron
#	|| (defined($patron_pwd) && !$patron->check_password($patron_pwd))) {
#	$trans->screen_msg("Invalid Patron.");
#
#	return $trans;
#    }
#
#    $item = new ILS::Item ($item_id || $title_id);
#    if (!$item) {
#	$trans->screen_msg("No such item.");
#
#	# END TRANSACTION (conditionally)
#	return $trans;
#    } elsif ($item->fee && ($fee_ack ne 'Y')) {
#	$trans->screen_msg = "Fee required to place hold.";
#
#	# END TRANSACTION (conditionally)
#	return $trans;
#    }
#
#    $hold = {
#	item_id         => $item->id,
#	patron_id       => $patron->id,
#	expiration_date => $expiry_date,
#	pickup_location => $pickup_location,
#	hold_type       => $hold_type,
#    };
#
#    $trans->ok(1);
#    $trans->patron($patron);
#    $trans->item($item);
#    $trans->pickup_location($pickup_location);
#
#    push(@{$item->hold_queue}, $hold);
#    push(@{$patron->{hold_items}}, $hold);
#
#
#    # END TRANSACTION
#    return $trans;
#}
#
#sub cancel_hold {
#    my ($self, $patron_id, $patron_pwd, $item_id, $title_id) = @_;
#    my ($patron, $item, $hold);
#    my $trans;
#
#    $trans = new ILS::Transaction::Hold;
#
#    # BEGIN TRANSACTION
#    $patron = new ILS::Patron $patron_id;
#    if (!$patron) {
#	$trans->screen_msg("Invalid patron barcode.");
#
#	return $trans;
#    } elsif (defined($patron_pwd) && !$patron->check_password($patron_pwd)) {
#	$trans->screen_msg('Invalid patron password.');
#
#	return $trans;
#    }
#
#    $item = new ILS::Item ($item_id || $title_id);
#    if (!$item) {
#	$trans->screen_msg("No such item.");
#
#	# END TRANSACTION (conditionally)
#	return $trans;
#    }
#
#    # Remove the hold from the patron's record first
#    $trans->ok($patron->drop_hold($item_id));
#
#    if (!$trans->ok) {
#	# We didn't find it on the patron record
#	$trans->screen_msg("No such hold on patron record.");
#
#	# END TRANSACTION (conditionally)
#	return $trans;
#    }
#
#    # Now, remove it from the item record.  If it was on the patron
#    # record but not on the item record, we'll treat that as success.
#    foreach my $i (0 .. scalar @{$item->hold_queue}) {
#	$hold = $item->hold_queue->[$i];
#
#	if ($hold->{patron_id} eq $patron->id) {
#	    # found it: delete it.
#	    splice @{$item->hold_queue}, $i, 1;
#	    last;
#	}
#    }
#
#    $trans->screen_msg("Hold Cancelled.");
#    $trans->patron($patron);
#    $trans->item($item);
#
#    return $trans;
#}
#
#
## The patron and item id's can't be altered, but the
## date, location, and type can.
#sub alter_hold {
#    my ($self, $patron_id, $patron_pwd, $item_id, $title_id,
#	$expiry_date, $pickup_location, $hold_type, $fee_ack) = @_;
#    my ($patron, $item);
#    my $hold;
#    my $trans;
#
#    $trans = new ILS::Transaction::Hold;
#
#    # BEGIN TRANSACTION
#    $patron = new ILS::Patron $patron_id;
#    if (!$patron) {
#	$trans->screen_msg("Invalid patron barcode.");
#
#	return $trans;
#    }
#
#    foreach my $i (0 .. scalar @{$patron->{hold_items}}) {
#	$hold = $patron->{hold_items}[$i];
#
#	if ($hold->{item_id} eq $item_id) {
#	    # Found it.  So fix it.
#	    $hold->{expiration_date} = $expiry_date if $expiry_date;
#	    $hold->{pickup_location} = $pickup_location if $pickup_location;
#	    $hold->{hold_type} = $hold_type if $hold_type;
#
#	    $trans->ok(1);
#	    $trans->screen_msg("Hold updated.");
#	    $trans->patron($patron);
#	    $trans->item(new ILS::Item $hold->{item_id});
#	    last;
#	}
#    }
#
#    # The same hold structure is linked into both the patron's
#    # list of hold items and into the queue of outstanding holds
#    # for the item, so we don't need to search the hold queue for
#    # the item, since it's already been updated by the patron code.
#
#    if (!$trans->ok) {
#	$trans->screen_msg("No such outstanding hold.");
#    }
#
#    return $trans;
#}
#
#sub renew {
#    my ($self, $patron_id, $patron_pwd, $item_id, $title_id,
#	$no_block, $nb_due_date, $third_party,
#	$item_props, $fee_ack) = @_;
#    my ($patron, $item);
#    my $trans;
#
#    $trans = new ILS::Transaction::Renew;
#
#    $trans->patron($patron = new ILS::Patron $patron_id);
#    if (!$patron) {
#	$trans->screen_msg("Invalid patron barcode.");
#
#	return $trans;
#    } elsif (!$patron->renew_ok) {
#
#	$trans->screen_msg("Renewals not allowed.");
#
#	return $trans;
#    }
#
#    if (defined($title_id)) {
#	# renewing a title, rather than an item (sort of)
#	# This is gross, but in a real ILS it would be better
#	foreach my $i (@{$patron->{items}}) {
#	    $item = new ILS::Item $i;
#	    last if ($title_id eq $item->title_id);
#	    $item = undef;
#	}
#    } else {
#	foreach my $i (@{$patron->{items}}) {
#	    if ($i == $item_id) {
#		# We have it checked out
#		$item = new ILS::Item $item_id;
#		last;
#	    }
#	}
#    }
#
#    if (!defined($item)) {
#	# It's not checked out to $patron_id
#	$trans->screen_msg("Item not checked out to " . $patron->name);
#    } elsif (!$item->available($patron_id)) {
#	 $trans->screen_msg("Item has outstanding holds");
#    } else {
#	$trans->item($item);
#	$trans->renewal_ok(1);
#
#	$trans->desensitize(0);	# It's already checked out
#
#	if ($no_block eq 'Y') {
#	    $item->{due_date} = $nb_due_date;
#	} else {
#	    $item->{due_date} = time + (14*24*60*60); # two weeks
#	}
#	if ($item_props) {
#	    $item->{sip_item_properties} = $item_props;
#	}
#	$trans->ok(1);
#	$trans->renewal_ok(1);
#
#	return $trans;
#    }
#
#    return $trans;
#}
#
#sub renew_all {
#    my ($self, $patron_id, $patron_pwd, $fee_ack) = @_;
#    my ($patron, $item_id);
#    my $trans;
#
#    $trans = new ILS::Transaction::RenewAll;
#
#    $trans->patron($patron = new ILS::Patron $patron_id);
#    if (defined $patron) {
#	syslog("LOG_DEBUG", "ILS::renew_all: patron '%s': renew_ok: %s",
#	       $patron->name, $patron->renew_ok);
#    } else {
#	syslog("LOG_DEBUG", "ILS::renew_all: Invalid patron id: '%s'",
#	       $patron_id);
#    }
#
#    if (!defined($patron)) {
#	$trans->screen_msg("Invalid patron barcode.");
#	return $trans;
#    } elsif (!$patron->renew_ok) {
#	$trans->screen_msg("Renewals not allowed.");
#	return $trans;
#    } elsif (defined($patron_pwd) && !$patron->check_password($patron_pwd)) {
#	$trans->screen_msg("Invalid patron password.");
#	return $trans;
#    }
#
#    foreach $item_id (@{$patron->{items}}) {
#	my $item = new ILS::Item $item_id;
#
#	if (!defined($item)) {
#	    syslog("LOG_WARNING",
#		   "renew_all: Invalid item id associated with patron '%s'",
#		   $patron->id);
#	    next;
#	}
#
#	if (@{$item->hold_queue}) {
#	    # Can't renew if there are outstanding holds
#	    push @{$trans->unrenewed}, $item_id;
#	} else {
#	    $item->{due_date} = time + (14*24*60*60); # two weeks hence
#	    push @{$trans->renewed}, $item_id;
#	}
#    }
#
#    $trans->ok(1);
#
#    return $trans;
#}

1;
