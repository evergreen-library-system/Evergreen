package OpenILS::SIP::Item;
use strict; use warnings;

use Sys::Syslog qw(syslog);
use Carp;

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Circ::ScriptBuilder;
# use Data::Dumper;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils qw/:datetime/;
use DateTime::Format::ISO8601;
use OpenSRF::Utils::SettingsClient;
my $U = 'OpenILS::Application::AppUtils';

my %item_db;

# 0 means read-only
# 1 means read/write    Actually, gloves are off.  Set what you like.

my %fields = (
    id => 0,
#   sip_media_type     => 0,
    sip_item_properties => 0,
#   magnetic_media     => 0,
    permanent_location => 0,
    current_location   => 0,
#   print_line         => 1,
#   screen_msg         => 1,
#   itemnumber         => 0,
#   biblionumber       => 0,
    hold               => 0,
    hold_patron_bcode  => 0,
    hold_patron_name   => 0,
    barcode            => 0,
    onloan             => 0,
    collection_code    => 0,
    destination_loc    => 0,
    call_number        => 0,
    enumchron          => 0,
    location           => 0,
    author             => 0,
    title              => 0,
    copy               => 0,
    volume             => 0,
    record             => 0,
    mods               => 0,
);

our $AUTOLOAD;
sub DESTROY { } # keeps AUTOLOAD from catching inherent DESTROY calls

sub AUTOLOAD {
    my $self = shift;
    my $class = ref($self) or croak "$self is not an object";
    my $name = $AUTOLOAD;

    $name =~ s/.*://;

    unless (exists $fields{$name}) {
        croak "Cannot access '$name' field of class '$class'";
    }

    if (@_) {
        # $fields{$name} or croak "Field '$name' of class '$class' is READ ONLY.";  # nah, go ahead
        return $self->{$name} = shift;
    } else {
        return $self->{$name};
    }
}


sub new {
    my ($class, $item_id) = @_;
    my $type = ref($class) || $class;
    my $self = bless( {}, $type );

    syslog('LOG_DEBUG', "OILS: Loading item $item_id...");
    return undef unless $item_id;

    my $e = OpenILS::SIP->editor();

    my $copy = $e->search_asset_copy(
		[
			{ barcode => $item_id, deleted => 'f' },
			{
				flesh => 3,
				flesh_fields => {
					acp => [ 'circ_lib', 'call_number', 'status', 'stat_cat_entry_copy_maps' ],
					acn => [ 'owning_lib', 'record' ],
                    ascecm => [ 'stat_cat', 'stat_cat_entry' ],
				}
			}
		]
    )->[0];

	if(!$copy) {
		syslog("LOG_DEBUG", "OILS: Item '%s' : not found", $item_id);
		return undef;
	}

    my $circ = $e->search_action_circulation([
        {
            target_copy => $copy->id,
            stop_fines_time => undef, 
            checkin_time => undef
        },
        {
            flesh => 2,
            flesh_fields => {
                circ => ['usr'],
                au => ['card']
            }
        }
    ])->[0];

    if($circ) {

        my $user = $circ->usr;
        my $bc = ($user->card) ? $user->card->barcode : '';
        $self->{patron} = $bc;
        $self->{patron_object} = $user;

        syslog('LOG_DEBUG', "OILS: Open circulation exists on $item_id : user = $bc");
    }

    $self->{id}         = $item_id;
    $self->{copy}       = $copy;
    $self->{volume}     = $copy->call_number;
    $self->{record}     = $copy->call_number->record;
    $self->{call_number} = $copy->call_number->label;
    $self->{mods}       = $U->record_to_mvr($self->{record}) if $self->{record}->marc;
    $self->{transit}    = $self->fetch_transit;
    $self->{hold}       = $self->fetch_hold;


    # use the non-translated version of the copy location as the
    # collection code, since it may be used for additional routing
    # purposes by the SIP client.  Config option?
    $self->{collection_code} = 
        $e->retrieve_asset_copy_location([
            $copy->location, {no_i18n => 1}])->name;


    if($self->{transit}) {
        $self->{destination_loc} = $self->{transit}->dest->shortname;

    } elsif($self->{hold}) {
        $self->{destination_loc} = $self->{hold}->pickup_lib->shortname;
    }

    syslog("LOG_DEBUG", "OILS: Item('$item_id'): found with title '%s'", $self->title_id);

    my $config = OpenILS::SIP->config();    # FIXME : will not always match!
    my $legacy = $config->{implementation_config}->{legacy_script_support} || undef;

    if( defined $legacy ) {
        $self->{legacy_script_support} = ($legacy =~ /t(rue)?/io) ? 1 : 0;
        syslog("LOG_DEBUG", "legacy_script_support is set in SIP config: " . $self->{legacy_script_support});

    } else {
        my $lss = OpenSRF::Utils::SettingsClient->new->config_value(
            apps         => 'open-ils.circ',
            app_settings => 'legacy_script_support'
        );
        $self->{legacy_script_support} = ($lss =~ /t(rue)?/io) ? 1 : 0;
        syslog("LOG_DEBUG", "legacy_script_support is set in SRF config: " . $self->{legacy_script_support});
    }

    return $self;
}

# fetch copy transit
sub fetch_transit {
    my $self = shift;
    my $copy = $self->{copy} or return;
    my $e = OpenILS::SIP->editor();

    if ($copy->status->id == OILS_COPY_STATUS_IN_TRANSIT) {
        my $transit = $e->search_action_transit_copy([
            {
                target_copy    => $copy->id,    # NOT barcode ($self->id)
                dest_recv_time => undef
            },
            {
                flesh => 1,
                flesh_fields => {
                    atc => ['dest']
                }
            }
        ])->[0];

        syslog('LOG_WARNING', "OILS: Item(".$copy->barcode.
            ") status is In Transit, but no action.transit_copy found!") unless $transit;
            
        return $transit;
    }
    
    return undef;
}

# fetch captured hold.
# Assume transit has already beeen fetched
sub fetch_hold {
    my $self = shift;
    my $copy = $self->{copy} or return;
    my $e = OpenILS::SIP->editor();

    if( ($copy->status->id == OILS_COPY_STATUS_ON_HOLDS_SHELF) ||
        ($self->{transit} and $self->{transit}->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF) ) {
        # item has been captured for a hold

        my $hold = $e->search_action_hold_request([
            {
                current_copy        => $copy->id,
                capture_time        => {'!=' => undef},
                cancel_time         => undef,
                fulfillment_time    => undef
            },
            {
                limit => 1,
                flesh => 1,
                flesh_fields => {
                    ahr => ['pickup_lib']
                }
            }
        ])->[0];

        syslog('LOG_WARNING', "OILS: Item(".$copy->barcode.
            ") is captured for a hold, but there is no matching hold request") unless $hold;

        return $hold;
    }

    return undef;
}

sub run_attr_script {
	my $self = shift;
	return 1 if $self->{ran_script};
	$self->{ran_script} = 1;

    if($self->{legacy_script_support}){

        syslog('LOG_DEBUG', "Legacy script support is ON");
        my $config = OpenILS::SIP->config();
        my $path               = $config->{implementation_config}->{scripts}->{path};
        my $item_config_script = $config->{implementation_config}->{scripts}->{item_config};

        $path = ref($path) eq 'ARRAY' ? $path : [$path];
        my $path_str = join(", ", @$path);

        syslog('LOG_DEBUG', "OILS: Script path = [$path_str], Item config script = $item_config_script");

        my $runner = OpenILS::Application::Circ::ScriptBuilder->build({
            copy   => $self->{copy},
            editor => OpenILS::SIP->editor(),
        });

        $runner->add_path($_) for @$path;
        $runner->load($item_config_script);

        unless( $self->{item_config_result} = $runner->run ) {      # assignment, not comparison
            $runner->cleanup;
            warn "Item config script [$path_str : $item_config_script] failed to run: $@\n";
            syslog('LOG_ERR', "OILS: Item config script [$path_str : $item_config_script] failed to run: $@");
            return undef;
        }

        $runner->cleanup;

    } else {

        # use the in-db circ modifier configuration 
        my $config = {magneticMedia => 'f', SIPMediaType => '001'};     # defaults
        my $mod = $self->{copy}->circ_modifier;

        if($mod) {
            my $mod_obj = OpenILS::SIP->editor()->retrieve_config_circ_modifier($mod);
            if($mod_obj) {
                $config->{magneticMedia} = $mod_obj->magnetic_media;
                $config->{SIPMediaType}  = $mod_obj->sip2_media_type;
            }
        }

        $self->{item_config_result} = { item_config => $config };
    }

	return 1;
}

sub magnetic_media {
    my $self = shift;
    $self->magnetic(@_);
}
sub magnetic {
    my $self = shift;
    return 0 unless $self->run_attr_script;
    my $mag = $self->{item_config_result}->{item_config}->{magneticMedia} || '';
    syslog('LOG_DEBUG', "OILS: magnetic = $mag");
    return ($mag and $mag =~ /t(rue)?/io) ? 1 : 0;
}

sub sip_media_type {
    my $self = shift;
    return 0 unless $self->run_attr_script;
    my $media = $self->{item_config_result}->{item_config}->{SIPMediaType} || '';
    syslog('LOG_DEBUG', "OILS: media type = $media");
    return ($media) ? $media : '001';
}

sub title_id {
    my $self = shift;
    my $t =  ($self->{mods}) ? $self->{mods}->title : $self->{copy}->dummy_title;
    return OpenILS::SIP::clean_text($t);
}

sub permanent_location {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{copy}->circ_lib->shortname);
}

sub current_location {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{copy}->circ_lib->shortname);
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
    my $stat = $self->{copy}->status->id;

    return '02' if $stat == OILS_COPY_STATUS_ON_ORDER;
    return '03' if $stat == OILS_COPY_STATUS_AVAILABLE;
    return '04' if $stat == OILS_COPY_STATUS_CHECKED_OUT;
    return '06' if $stat == OILS_COPY_STATUS_IN_PROCESS;
    return '08' if $stat == OILS_COPY_STATUS_ON_HOLDS_SHELF;
    return '09' if $stat == OILS_COPY_STATUS_RESHELVING;
    return '10' if $stat == OILS_COPY_STATUS_IN_TRANSIT;
    return '12' if $stat == OILS_COPY_STATUS_LOST;
    return '13' if $stat == OILS_COPY_STATUS_MISSING;
        
    return '01';
}

sub sip_security_marker {
    return '02';    # FIXME? 00-other; 01-None; 02-Tattle-Tape Security Strip (3M); 03-Whisper Tape (3M)
}

sub sip_fee_type {
    my $self = shift;
    # Return '06' for rental unless the fee is a deposit, or there is
    # no fee. In the latter cases, return '01'.
    return ($self->{copy}->deposit_amount > 0.0 && $self->{copy}->deposit =~ /^f/i) ? '06' : '01';
}

sub fee {
    my $self = shift;
    return $self->{copy}->deposit_amount;
}


sub fee_currency {
	my $self = shift;
	return OpenILS::SIP->config()->{implementation_config}->{currency};
}

sub owner {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{copy}->circ_lib->shortname);
}

sub hold_queue {
    my $self = shift;
    return [];
}

sub hold_queue_position {       # TODO
    my ($self, $patron_id) = @_;
    return 1;
}

sub due_date {
    my $self = shift;

    # this should force correct circ fetching
    require OpenILS::Utils::CStoreEditor;
    my $e = OpenILS::Utils::CStoreEditor->new(xact => 1);
    #my $e = OpenILS::SIP->editor();

    my $circ = $e->search_action_circulation(
        { target_copy => $self->{copy}->id, checkin_time => undef } )->[0];

    $e->rollback;

    if( !$circ ) {
        syslog('LOG_INFO', "OILS: No open circ found for copy");
        return 0;
    }

    my $due = OpenILS::SIP->format_date($circ->due_date, 'due');
    syslog('LOG_DEBUG', "OILS: Found item due date = $due");
    return $due;
}

sub recall_date {       # TODO
    my $self = shift;
    return 0;
}


# Note: If the held item is in transit, this will be an approximation of shelf 
# expire time, since the time is not set until the item is  checked in at the pickup location
my %shelf_expire_setting_cache;
sub hold_pickup_date {  
    my $self = shift;
    my $copy = $self->{copy};
    my $hold = $self->{hold} or return 0;

    my $date = $hold->shelf_expire_time;

    if(!$date) {
        # hold has not hit the shelf.  create a best guess.

        my $interval = $shelf_expire_setting_cache{$hold->pickup_lib->id} ||
            $U->ou_ancestor_setting_value(
                $hold->pickup_lib->id, 
                'circ.holds.default_shelf_expire_interval');

        $shelf_expire_setting_cache{$hold->pickup_lib->id} = $interval;

        if($interval) {
            my $seconds = OpenSRF::Utils->interval_to_seconds($interval);
            $date = DateTime->now->add(seconds => $seconds);
            $date = $date->strftime('%FT%T%z') if $date;
        }
    }

    return OpenILS::SIP->format_date($date) if $date;

    return 0;
}

# message to display on console
sub screen_msg {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{screen_msg}) || '';
}


# reciept printer
sub print_line {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{print_line}) || '';
}


# An item is available for a patron if
# 1) It's not checked out and (there's no hold queue OR patron
#    is at the front of the queue)
# OR
# 2) It's checked out to the patron and there's no hold queue
sub available {
    my ($self, $for_patron) = @_;

    my $stat = $self->{copy}->status->id;
    return 1 if 
        $stat == OILS_COPY_STATUS_AVAILABLE or
        $stat == OILS_COPY_STATUS_RESHELVING;

    return 0;
}

sub extra_fields {
    my( $self ) = @_;
    my $extra_fields = {};
    my $c = $self->{copy};
    foreach my $stat_cat_entry (@{$c->stat_cat_entry_copy_maps}) {
        my $stat_cat = $stat_cat_entry->stat_cat;
        next unless ($stat_cat->sip_field);
        my $value = $stat_cat_entry->stat_cat_entry->value;
        if(defined $stat_cat->sip_format && length($stat_cat->sip_format) > 0) { # Has a format string?
            if($stat_cat->sip_format =~ /^\|(.*)\|$/) { # Regex match?
                if($value =~ /($1)/) { # If we have a match
                    if(defined $2) { # Check to see if they embedded a capture group
                        $value = $2; # If so, use it
                    }
                    else { # No embedded capture group?
                        $value = $1; # Use our outer one
                    }
                }
                else { # No match?
                    $value = ''; # Empty string. Will be checked for below.
                }
            }
            else { # Not a regex match - Try sprintf match (looking for a %s, if any)
                $value = sprintf($stat_cat->sip_format, $value);
            }
        }
        next unless length($value) > 0; # No value = no export
        $value =~ s/\|//g; # Remove all lingering pipe chars for sane output purposes
        $extra_fields->{ $stat_cat->sip_field } = [] unless (defined $extra_fields->{$stat_cat->sip_field});
        push(@{$extra_fields->{ $stat_cat->sip_field}}, $value);
    }
    return $extra_fields;
}


1;
__END__

=head1 NAME

OpenILS::SIP::Item - SIP abstraction layer for OpenILS Items.

=head1 DESCRIPTION

=head2 owning_lib vs. circ_lib

In Evergreen, owning_lib is the org unit that purchased the item, the place to which the item 
should return after it's done rotating/floating to other branches (via staff intervention),
or some combination of those.  The owning_lib, however, is not necessarily where the item
should be going "right now" or where it should return to by default.  That would be the copy
circ_lib or the transit destination.  (In fact, the item may B<never> go to the owning_lib for
its entire existence).  In the context of SIP, the circ_lib more accurately describes the item's
permanent location, i.e. where it needs to be sent if it's not en route to somewhere else.

This confusion extends also to the SIP extension field of "owner".  It means that the SIP owner does not 
correspond to EG's asset.volume.owning_lib, mainly because owning_lib is effectively the "ultimate
owner" but not necessarily the "current owner".  Because we populate SIP fields with circ_lib, the
owning_lib is unused by SIP.  

=head1 TODO

Holds queue logic

=cut
