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
    #   sip_media_type      => 0,
    sip_item_properties => 0,
    #   magnetic_media      => 0,
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
					acp => [ 'circ_lib', 'call_number', 'status' ],
					acn => [ 'owning_lib', 'record' ],
				}
			}
		]
    );


    $copy = $copy->[0];

	if(!$copy) {
		syslog("LOG_DEBUG", "OILS: Item '%s' : not found", $item_id);
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

        syslog('LOG_DEBUG', "OILS: Open circulation exists on $item_id : user = $bc");
    }

    $self->{id}     = $item_id;
    $self->{copy}   = $copy;
    $self->{volume} = $copy->call_number;
    $self->{record} = $copy->call_number->record;
    $self->{mods}   = $U->record_to_mvr($self->{record}) if $self->{record}->marc;

    syslog("LOG_DEBUG", "OILS: Item('$item_id'): found with title '%s'", $self->title_id);

    my $config = OpenILS::SIP->config();

    if( defined $config->{implementation_config}->{legacy_script_support} ) {
        $self->{legacy_script_support} = 
            ($config->{implementation_config}->{legacy_script_support} =~ /true/io);
    } else {
        $self->{legacy_script_support} = 
            OpenSRF::Utils::SettingsClient->new->config_value(
                apps => 'open-ils.circ' => app_settings => 'legacy_script_support')
    }

    return $self;
}

sub run_attr_script {
	my $self = shift;
	return 1 if $self->{ran_script};
	$self->{ran_script} = 1;

    if($self->{legacy_script_support}){

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
            my $mod_obj = OpenILS::SIP->editor()->search_config_circ_modifier($mod);
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
    my $mag = $self->{item_config_result}->{item_config}->{magneticMedia};
    syslog('LOG_DEBUG', "OILS: magnetic = $mag");
    return ($mag and $mag =~ /t(rue)?/io) ? 1 : 0;
}

sub sip_media_type {
    my $self = shift;
    return 0 unless $self->run_attr_script;
    my $media = $self->{item_config_result}->{item_config}->{SIPMediaType};
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
    return OpenILS::SIP::clean_text($self->{volume}->owning_lib->name);
}

sub current_location {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{copy}->circ_lib->name);
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
        
    return 01;
}

sub sip_security_marker {
    return '02';    # FIXME? 00-other; 01-None; 02-Tattle-Tape Security Strip (3M); 03-Whisper Tape (3M)
}

sub sip_fee_type {
    return '01';    # FIXME? 01-09 enumerated in spec.  We just use O1-other/unknown.
}

sub fee {           # TODO
    my $self = shift;
    return 0;
}


sub fee_currency {
	my $self = shift;
	return OpenILS::SIP->config()->{implementation_config}->{currency};
}

sub owner {
    my $self = shift;
    return OpenILS::SIP::clean_text($self->{volume}->owning_lib->name);
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

sub hold_pickup_date {  # TODO
    my $self = shift;
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


1;
