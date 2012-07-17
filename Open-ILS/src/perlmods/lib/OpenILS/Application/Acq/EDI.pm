package OpenILS::Application::Acq::EDI;
use base qw/OpenILS::Application/;

use strict; use warnings;

use IO::Scalar;

use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;

use OpenILS::Application::Acq::Lineitem;
use OpenILS::Utils::RemoteAccount;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::EDI::Translator;

use OpenILS::Utils::LooseEDI;
use Business::EDI;

use Data::Dumper;
our $verbose = 0;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    # $self->{args} = {};
    return $self;
}

# our $reasons = {};   # cache for acq.cancel_reason rows ?

our $translator;

sub translator {
    return $translator ||= OpenILS::Application::Acq::EDI::Translator->new(@_);
}

my %map = (
    host     => 'remote_host',
    username => 'remote_user',
    password => 'remote_password',
    account  => 'remote_account',
    # in_dir   => 'remote_path',   # field_map overrides path with in_dir
    path     => 'remote_path',
);


## Just for debugging stuff:
sub add_a_msg {
    my ($self, $conn) = @_;
    my $e = new_editor(xact=>1);
    my $incoming = Fieldmapper::acq::edi_message->new;
    $incoming->edi("This is content");
    $incoming->account(1);
    $incoming->remote_file('in/some_file.edi');
    $e->create_acq_edi_message($incoming);;
    $e->commit;
}
# __PACKAGE__->register_method( method => 'add_a_msg', api_name => 'open-ils.acq.edi.add_a_msg');  # debugging

__PACKAGE__->register_method(
	method    => 'retrieve',
	api_name  => 'open-ils.acq.edi.retrieve',
    authoritative => 1,
	signature => {
        desc   => 'Fetch incoming message(s) from EDI accounts.  ' .
                  'Optional arguments to restrict to one vendor and/or a max number of messages.  ' .
                  'Note that messages are not parsed or processed here, just fetched and translated.',
        params => [
            {desc => 'Authentication token',        type => 'string'},
            {desc => 'Vendor ID (undef for "all")', type => 'number'},
            {desc => 'Date Inactive Since',         type => 'string'},
            {desc => 'Max Messages Retrieved',      type => 'number'}
        ],
        return => {
            desc => 'List of new message IDs (empty if none)',
            type => 'array'
        }
    }
);

sub retrieve_core {
    my ($self, $set, $max, $e, $test) = @_;    # $e is a working editor

    $e   ||= new_editor();
    $set ||= __PACKAGE__->retrieve_vendors($e);

    my @return = ();
    my $vcount = 0;
    foreach my $account (@$set) {
        my $count = 0;
        my $server;
        $logger->info("EDI check for vendor " . ++$vcount . " of " . scalar(@$set) . ": " . $account->host);
        unless ($server = __PACKAGE__->remote_account($account)) {   # assignment, not comparison
            $logger->err(sprintf "Failed remote account mapping for %s (%s)", $account->host, $account->id);
            next;
        };
#       my $rf_starter = './';  # default to current dir
        if ($account->in_dir) { 
            if ($account->in_dir =~ /\*+.*\//) {
                $logger->err("EDI in_dir has a slash after an asterisk in value: '" . $account->in_dir . "'.  Skipping account with indeterminate target dir!");
                next;
            }
#           $rf_starter = $account->in_dir;
#           $rf_starter =~ s/((\/)?[^\/]*)\*+[^\/]*$//;  # kill up to the first (possible) slash before the asterisk: keep the preceeding static dir
#           $rf_starter .= '/' if $rf_starter or $2;   # recap the dir, or replace leading "/" if there was one (but don't add if empty)
        }
        my @files    = ($server->ls({remote_file => ($account->in_dir || './')}));
        my @ok_files = grep {$_ !~ /\/\.?\.$/ and $_ ne '0'} @files;
        $logger->info(sprintf "%s of %s files at %s/%s", scalar(@ok_files), scalar(@files), $account->host, $account->in_dir);   
        # $server->remote_path(undef);
        foreach my $remote_file (@ok_files) {
            # my $remote_file = $rf_starter . $_;
            my $description = sprintf "%s/%s", $account->host, $remote_file;
            
            # deduplicate vs. acct/filenames already in DB
            my $hits = $e->search_acq_edi_message([
                {
                    account     => $account->id,
                    remote_file => $remote_file,
                    status      => {'in' => [qw/ processed /]},     # if it never got processed, go ahead and get the new one (try again)
                    # create_time => 'NOW() - 60 DAYS',     # if we wanted to allow filenames to be reused after a certain time
                    # ideally we would also use the date from FTP, but that info isn't available via RemoteAccount
                }
                # { flesh => 1, flesh_fields => {...}, }
            ]);
            if (scalar(@$hits)) {
                $logger->debug("EDI: $remote_file already retrieved.  Skipping");
                warn "EDI: $remote_file already retrieved.  Skipping";
                next;
            }

            ++$count;
            $max and $count > $max and last;
            $logger->info(sprintf "%s of %s targets: %s", $count, scalar(@ok_files), $description);
            print sprintf "%s of %s targets: %s\n", $count, scalar(@ok_files), $description;
            if ($test) {
                push @return, "test_$count";
                next;
            }
            my $content;
            my $io = IO::Scalar->new(\$content);
            unless ( $server->get({remote_file => $remote_file, local_file => $io}) ) {
                $logger->error("(S)FTP get($description) failed");
                next;
            }
            my $incoming = __PACKAGE__->process_retrieval($content, $remote_file, $server, $account->id, $e);
#           $server->delete(remote_file => $_);   # delete remote copies of saved message
            push @return, $incoming->id;
        }
    }
    return \@return;
}

# my $in = OpenILS::Application::Acq::EDI->process_retrieval($file_content, $remote_filename, $server, $account_id, $editor);

sub process_retrieval {
    my $incoming = Fieldmapper::acq::edi_message->new;
    my ($class, $content, $remote, $server, $account_or_id, $e) = @_;
    $content or return;
    $e ||= new_editor;

    my $account = __PACKAGE__->record_activity( $account_or_id, $e );

    my $z;  # must predeclare
    $z = ( $content =~ s/('UNH\+\d+\+ORDRSP:)0(:96A:UN')/$1D$2/g )
        and $logger->warn("Patching bogus spec reference ORDRSP:0:96A:UN => ORDRSP:D:96A:UN ($z times)");  # Hack/fix some faulty "0" in (B&T) data

    $incoming->remote_file($remote);
    $incoming->account($account->id);
    $incoming->edi($content);
    $incoming->message_type(($content =~ /'UNH\+\d+\+(\S{6}):/) ? $1 : 'ORDRSP');   # cheap sniffing, ORDRSP fallback
    __PACKAGE__->attempt_translation($incoming);
    $e->xact_begin;
    $e->create_acq_edi_message($incoming);
    $e->xact_commit;
    # refresh: send process_jedi the updated row
    $e->xact_begin;

    # LFW: I really don't understand in what sense you could call this
    # message 'outgoing', except from the vendor's point of view?
    my $outgoing = $e->retrieve_acq_edi_message($incoming->id);  # refresh again!
    $e->xact_rollback;
    my $res = __PACKAGE__->process_jedi($outgoing, $server, $account, $e);
    $e->xact_begin;
    $outgoing = $e->retrieve_acq_edi_message($incoming->id);  # refresh again!
    $e->xact_rollback;
    $outgoing->status($res ? 'processed' : 'proc_error');
    if ($res) {
        $e->xact_begin;
        $e->update_acq_edi_message($outgoing);
        $e->xact_commit;
    }
    return $outgoing;
}

# ->send_core
# $account     is a Fieldmapper object for acq.edi_account row
# $messageset  is an arrayref with acq.edi_message.id values
# $e           is optional editor object
sub send_core {
    my ($class, $account, $message_ids, $e) = @_;    # $e is a working editor

    ($account and scalar @$message_ids) or return;
    $e ||= new_editor();

    $e->xact_begin;
    my @messageset = map {$e->retrieve_acq_edi_message($_)} @$message_ids;
    $e->xact_rollback;
    my $m_count = scalar(@messageset);
    (scalar(@$message_ids) == $m_count) or
        $logger->warn(scalar(@$message_ids) - $m_count . " bad IDs passed to send_core (ignored)");

    my $log_str = sprintf "EDI send to edi_account %s (%s)", $account->id, $account->host;
    $logger->info("$log_str: $m_count message(s)");
    $m_count or return;

    my $server;
    my $server_error;
    unless ($server = __PACKAGE__->remote_account($account, 1)) {   # assignment, not comparison
        $logger->error("Failed remote account connection for $log_str");
        $server_error = 1;
    };
    foreach (@messageset) {
        $_ or next;     # we already warned about bum ids
        my ($res, $error);
        if ($server_error) {
            $error = "Server error: Failed remote account connection for $log_str"; # already told $logger, this is to update object below
        } elsif (! $_->edi) {
            $logger->error("Message (id " . $_->id. ") for $log_str has no EDI content");
            $error = "EDI empty!";
        } elsif ($res = $server->put({remote_path => $account->path, content => $_->edi, single_ext => 1})) {
            #  This is the successful case!
            $_->remote_file($res);
            $_->status('complete');
            $_->process_time('NOW');    # For outbound files, sending is the end of processing on the EG side.
            $logger->info("Sent message (id " . $_->id. ") via $log_str");
        } else {
            $logger->error("(S)FTP put to $log_str FAILED: " . ($server->error || 'UNKOWNN'));
            $error = "put FAILED: " . ($server->error || 'UNKOWNN');
        }
        if ($error) {
            $_->error($error);
            $_->error_time('NOW');
        }
        $logger->info("Calling update_acq_edi_message");
        $e->xact_begin;
        unless ($e->update_acq_edi_message($_)) {
             $logger->error("EDI send_core update_acq_edi_message failed for message object: " . Dumper($_));
             OpenILS::Application::Acq::EDI::Translator->debug_file(Dumper($_              ), '/tmp/update_acq_edi_message.FAIL');
             OpenILS::Application::Acq::EDI::Translator->debug_file(Dumper($_->to_bare_hash), '/tmp/update_acq_edi_message.FAIL.to_bare_hash');
        }
        # There's always an update, even if we failed.
        $e->xact_commit;
        __PACKAGE__->record_activity($account, $e);  # There's always an update, even if we failed.
    }
    return \@messageset;
}

#  attempt_translation does not touch the DB, just the object.  
sub attempt_translation {
    my ($class, $edi_message, $to_edi) = @_;
    my $tran  = translator();
    my $ret   = $to_edi ? $tran->json2edi($edi_message->jedi) : $tran->edi2json($edi_message->edi);
#   $logger->error("json: " . Dumper($json)); # debugging
    if (not $ret or (! ref($ret)) or $ret->is_fault) {      # RPC::XML::fault on failure
        $edi_message->status('trans_error');
        $edi_message->error_time('NOW');
        my $pre = "EDI Translator " . ($to_edi ? 'json2edi' : 'edi2json') . " failed";
        my $message = ref($ret) ? 
                      ("$pre, Error " . $ret->code . ": " . __PACKAGE__->nice_string($ret->string)) :
                      ("$pre: "                           . __PACKAGE__->nice_string($ret)        ) ;
        $edi_message->error($message);
        $logger->error(  $message);
        return;
    }
    $edi_message->status('translated');
    $edi_message->translate_time('NOW');
    if ($to_edi) {
        $edi_message->edi($ret->value);    # translator returns an object
    } else {
        $edi_message->jedi($ret->value);   # translator returns an object
    }
    return $edi_message;
}

sub retrieve_vendors {
    my ($self, $e, $vendor_id, $last_activity) = @_;    # $e is a working editor

    $e ||= new_editor();

    my $criteria = {'+acqpro' => {active => 't'}};
    $criteria->{'+acqpro'}->{id} = $vendor_id if $vendor_id;
    return $e->search_acq_edi_account([
        $criteria, {
            'join' => 'acqpro',
            flesh => 1,
            flesh_fields => {
                acqedi => ['provider']
            }
        }
    ]);
#   {"id":{"!=":null},"+acqpro":{"active":"t"}}, {"join":"acqpro", "flesh_fields":{"acqedi":["provider"]},"flesh":1}
}

# This is the SRF-exposed call, so it does checkauth

sub retrieve {
    my ($self, $conn, $auth, $vendor_id, $last_activity, $max) = @_;

    my $e = new_editor(authtoken=>$auth);
    unless ($e and $e->checkauth()) {
        $logger->warn("checkauth failed for authtoken '$auth'");
        return ();
    }
    # return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $li->purchase_order->ordering_agency);  # add permission here ?

    my $set = __PACKAGE__->retrieve_vendors($e, $vendor_id, $last_activity) or return $e->die_event;
    return __PACKAGE__->retrieve_core($e, $set, $max);
}


# field_map takes the hashref of vendor data with fields from acq.edi_account and 
# maps them to the argument style needed for RemoteAccount.  It also extrapolates
# data from the remote_host string for type and port, when available.

sub field_map {
    my $self   = shift;
    my $vendor = shift or return;
    my $no_override = @_ ? shift : 0;
    my %args = ();
    $verbose and $logger->warn("vendor: " . Dumper($vendor));
    foreach (keys %map) {
        $args{$map{$_}} = $vendor->$_ if defined $vendor->$_;
    }
    unless ($no_override) {
        $args{remote_path} = $vendor->in_dir;    # override "path" with "in_dir"
    }
    my $host = $args{remote_host} || '';
    ($host =~ s/^(S?FTP)://i    and $args{type} = uc($1)) or
    ($host =~ s/^(SSH|SCP)://i  and $args{type} = 'SCP' ) ;
     $host =~ s/:(\d+)$//       and $args{port} = $1;
    ($args{remote_host} = $host) =~ s#/+##;
    $verbose and $logger->warn("field_map: " . Dumper(\%args));
    return %args;
}


# The point of remote_account is to get the RemoteAccount object with args from the DB

sub remote_account {
    my ($self, $vendor, $outbound, $e) = @_;

    unless (ref($vendor)) {     # It's not a hashref/object.
        $vendor or return;      # If in fact it's nothing: abort!
                                # else it's a vendor_id string, so get the full vendor data
        $e ||= new_editor();
        my $set_of_one = $self->retrieve_vendors($e, $vendor) or return;
        $vendor = shift @$set_of_one;
    }

    return OpenILS::Utils::RemoteAccount->new(
        $self->field_map($vendor, $outbound)
    );
}

# takes account ID or account Fieldmapper object

sub record_activity {
    my ($class, $account_or_id, $e) = @_;
    $account_or_id or return;
    $e ||= new_editor();
    my $account = ref($account_or_id) ? $account_or_id : $e->retrieve_acq_edi_account($account_or_id);
    $logger->info("EDI record_activity calling update_acq_edi_account");
    $account->last_activity('NOW') or return;
    $e->xact_begin;
    $e->update_acq_edi_account($account) or $logger->warn("EDI: in record_activity, update_acq_edi_account FAILED");
    $e->xact_commit;
    return $account;
}

sub nice_string {
    my $class = shift;
    my $string = shift or return '';
    chomp($string);
    my $head   = @_ ? shift : 100;
    my $tail   = @_ ? shift :  25;
    (length($string) < $head + $tail) and return $string;
    my $h = substr($string,0,$head);
    my $t = substr($string, -1*$tail);
    $h =~s/\s*$//o;
    $t =~s/\s*$//o;
    return "$h ... $t";
    # return substr($string,0,$head) . "... " . substr($string, -1*$tail);
}

sub jedi2perl {
    my ($class, $jedi) = @_;
    $jedi or return;
    my $msg = OpenSRF::Utils::JSON->JSON2perl( $jedi );
    open (FOO, ">>/tmp/JSON2perl_dump.txt");
    print FOO Dumper($msg), "\n\n";
    close FOO;
    $logger->warn("Dumped JSON2perl to /tmp/JSON2perl_dump.txt");
    return $msg;
}

our @datecodes = (35, 359, 17, 191, 69, 76, 75, 79, 85, 74, 84, 223);
our @noop_6063 = (21);

# ->process_jedi($message, $server, $remote, $e)
# $message is an edi_message object
#
# This method has lots of logic to process ORDRSP messages (and theoretically
# OSTRPT messages) and to make changes based on those to EG acq objects.
# If it gets an INVOIC message, it hands that off to
# create_acq_invoice_from_edi() following a new model (this code all wants
# cleaned-up/refactored).
#
# This method currently returns an array of message objects, but no callers use
# that except in a boolean evaluation to test for success.  So don't count on
# that array being there or containing anything specific in the future: it
# might get changed.
sub process_jedi {
    my ($class, $message, $server, $remote, $e) = @_;
    $message or return;
    $server ||= {};  # context
    $remote ||= {};  # context
    $e ||= new_editor;
    my $jedi;
    unless (ref($message) and $jedi = $message->jedi) {     # assignment, not comparison
        $logger->warn("EDI process_jedi missing required argument (edi_message object with jedi)!");
        return;
    }
    my $perl  = __PACKAGE__->jedi2perl($jedi);
    my $error = '';
    if (ref($message) and not $perl) {
        $error = ($message->error || '') . " JSON2perl (jedi2perl) FAILED to convert jedi";
    }
    elsif (! $perl->{body}) {
        $error = "EDI interchange body not found!";
    } 
    elsif (! $perl->{body}->[0]) {
        $error = "EDI interchange body not a populated arrayref!";
    }
    if ($error) {
        $logger->warn($error);
        $message->error($error);
        $message->error_time('NOW');
        $e->xact_begin;
        $e->update_acq_edi_message($message) or $logger->warn("EDI update_acq_edi_message failed! $!");
        $e->xact_commit;
        return;
    }

# Crazy data structure.  Most of the arrays will be 1 element... we think.
# JEDI looks like:
# {'body' => [{'ORDERS' => [['UNH',{'0062' => '4635','S009' => {'0057' => 'EAN008','0051' => 'UN','0052' => 'D','0065' => 'ORDERS', ...
# 
# So you might access it like:
#   $obj->{body}->[0]->{ORDERS}->[0]->[0] eq 'UNH'

    $logger->info("EDI interchange body has " . scalar(@{$perl->{body}}) . " message(s)");
    my @ok_msg_codes = qw/ORDRSP OSTRPT INVOIC/;
    my @messages;
    my $i = 0;
    foreach my $part (@{$perl->{body}}) {
        $i++;
        unless (ref $part and scalar keys %$part) {
            $logger->warn("EDI interchange message $i lacks structure.  Skipping it.");
            next;
        }
        foreach my $key (keys %$part) {
            if (! grep {$_ eq $key} @ok_msg_codes) {     # We only do one type for now.  TODO: other types here
                $logger->warn("EDI interchange $i contains unhandled '$key' message.  Ignoring it.");
                next;
            }
            if ($key eq 'INVOIC') {
                # XXX TODO Maybe subclass O::U::LooseEDI::Message as
                # something like OpenILS::Acq::{VendorInvoice,OrderReponse},
                # each one knowing how to read itself and update EG acq
                # objects (not under OpenILS::Application perhaps).
                my $invoice_message =
                    new OpenILS::Utils::LooseEDI::Message($part->{$key});
                push @messages, $invoice_message if
                    $class->create_acq_invoice_from_edi(
                        $e, $invoice_message, $remote->provider
                    );
                next;
            }

            my $msg = __PACKAGE__->message_object($part->{$key}) or next;
            push @messages, $msg;

            my $bgm = $msg->xpath('BGM') or $logger->warn("EDI No BGM segment found?!");
            my $tag4343 = $msg->xpath('BGM/4343');
            my $tag1225 = $msg->xpath('BGM/1225');
            if (ref $tag4343) {
                $logger->info(sprintf "EDI $key BGM/4343 Response Type: %s - %s", $tag4343->value, $tag4343->label)
            } else {
                $logger->warn("EDI $key BGM/4343 Response Type Code unrecognized"); # next; #?
            }
            if (ref $tag1225) {
                $logger->info(sprintf "EDI $key BGM/1225 Message Function: %s - %s", $tag1225->value, $tag1225->label);
            } else {
                $logger->warn("EDI $key BGM/1225 Message Function Code unrecognized"); # next; #?
            }

            # TODO: currency check, just to be paranoid
            # *should* be unnecessary (vendor should reply in currency we send in ORDERS)
            # That begs a policy question: how to handle mismatch?  convert (bad accuracy), reject, or ignore?  I say ignore.

            # ALL those codes below are basically some form of (lastest) delivery date/time
            # see, e.g.: http://www.stylusstudio.com/edifact/D04B/2005.htm
            # The order is the order of definitiveness (first match wins)
            # Note: if/when we do serials via EDI, dates (and ranges/periods) will need massive special handling
            my @dates;
            my $ddate;

            foreach my $date ($msg->xpath('delivery_schedule')) {
                my $val_2005 = $date->xpath_value('DTM/2005') or next;
                (grep {$val_2005 eq $_} @datecodes) or next; # no match means some other kind of date we don't care about
                push @dates, $date;
            }
            if (@dates) {
                DATECODE: foreach my $dcode (@datecodes) {   # now cycle back through hits in order of dcode definitiveness
                    foreach my $date (@dates) {
                        $date->xpath_value('DTM/2005') == $dcode or next;
                        $ddate = $date->xpath_value('DTM/2380') and last DATECODE;
                        # TODO: conversion based on format specified in DTM/2379 (best encapsulated in Business::EDI)
                    }
                }
            }
            foreach my $detail ($msg->part('line_detail')) {
                my $eg_line = __PACKAGE__->eg_li($detail, $remote, $server->{remote_host}, $e) or next;
                my $li_date = $detail->xpath_value('DTM/2380') || $ddate;
                my $price   = $detail->xpath_value('line_price/PRI/5118') || '';
                $eg_line->expected_recv_time($li_date) if $li_date;
                $eg_line->estimated_unit_price($price) if $price;
                if (not $message->purchase_order) {                     # first good lineitem sets the message PO link
                    $message->purchase_order($eg_line->purchase_order); # EG $message object NOT Business::EDI $msg object
                    $e->xact_begin;
                    $e->update_acq_edi_message($message) or $logger->warn("EDI update_acq_edi_message (for PO number) failed! $!");
                    $e->xact_commit;
                }
                # $e->search_acq_edi_account([]);
                my $touches = 0;
                my $eg_lids = $e->search_acq_lineitem_detail({lineitem => $eg_line->id}); # should be the same as $eg_line->lineitem_details
                my $lidcount = scalar(@$eg_lids);
                $lidcount == $eg_line->item_count or $logger->warn(
                    sprintf "EDI: LI %s itemcount (%d) mismatch, %d LIDs found", $eg_line->id, $eg_line->item_count, $lidcount
                );
                foreach my $qty ($detail->part('all_QTY')) {
                    my $ubound   = $qty->xpath_value('6060') or next;   # nothing to do if qty is 0
                    my $val_6063 = $qty->xpath_value('6063');
                    $ubound > 0 or next; # don't be crazy!
                    if (! $val_6063) {
                        $logger->warn("EDI: Response for LI " . $eg_line->id . " specifies quantity $ubound with no 6063 code! Contact vendor to resolve.");
                        next;
                    }
                    
                    my $eg_reason = $e->retrieve_acq_cancel_reason(1200 + $val_6063);  # DB populated w/ 6063 keys in 1200's
                    if (! $eg_reason) {
                        $logger->warn("EDI: Unhandled quantity code '$val_6063' (LI " . $eg_line->id . ") $ubound items unprocessed");
                        next;
                    } elsif (grep {$val_6063 == $_} @noop_6063) {      # an FYI like "ordered quantity"
                        $ubound eq $lidcount
                            or $logger->warn("EDI: LI " . $eg_line->id . " -- Vendor says we ordered $ubound, but we have $lidcount LIDs!)");
                        next;
                    }
                    # elsif ($val_6063 == 83) { # backorder
                   #} elsif ($val_6063 == 85) { # cancel
                   #} elsif ($val_6063 == 12 or $val_6063 == 57 or $val_6063 == 84 or $val_6063 == 118) {
                            # despatched, in transit, urgent delivery, or quantity manifested
                   #}
                    if ($touches >= $lidcount) {
                        $logger->warn("EDI: LI "  . $eg_line->id . ", We already updated $touches of $lidcount LIDS, " .
                                      "but message wants QTY $ubound more set to " . $eg_reason->label . ".  Ignoring!");
                        next;
                    }
                    $e->xact_begin;
                    foreach (1 .. $ubound) {
                        my $eg_lid = shift @$eg_lids or $logger->warn("EDI: Used up all $lidcount LIDs!  Ignoring extra status " . $eg_reason->label);
                        $eg_lid or next;
                        $logger->debug(sprintf "Updating LID %s to %s", $eg_lid->id, $eg_reason->label);
                        $eg_lid->cancel_reason($eg_reason->id);
                        $e->update_acq_lineitem_detail($eg_lid);
                        $touches++;
                    }
                    $e->xact_commit;
                    if ($ubound == $eg_line->item_count) {
                        $eg_line->cancel_reason($eg_reason->id);    # if ALL the items have the same cancel_reason, the PO gets it too
                    }
                }
                $eg_line->edit_time('NOW'); # TODO: have this field automatically updated via ON UPDATE trigger.  
                $e->xact_begin;
                $e->update_acq_lineitem($eg_line) or $logger->warn("EDI: update_acq_lineitem FAILED");
                $e->xact_commit;
                # print STDERR "Lineitem update: ", Dumper($eg_line);
            }
        }
    }
    return \@messages;
}


# create_acq_invoice_from_edi() does what it sounds like it does for INVOIC
# messages.  For similar operation on ORDRSP messages, see the guts of
# process_jedi().
# Return boolean success indicator.
sub create_acq_invoice_from_edi {
    my ($class, $e, $invoice, $provider, $message) = @_;
    # $invoice is O::U::LooseEDI::Message, representing the EDI invoice message.
    # $provider is only a pkey
    # $message is Fieldmapper::acq::edi_message

    my $log_prefix = "create_acq_invoice_from_edi(..., <acq.edi_message #" .
        $message->id . ">): ";

    my $eg_inv = Fieldmapper::acq::invoice->new;

    $eg_inv->provider($provider);
    $eg_inv->shipper($provider);    # XXX Do we really have a meaningful way to
                                    # distinguish provider and shipper?
    $eg_inv->recv_method("EDI");

    # Find the buyer's identifier in the invoice.
    my $buyer_san;
    foreach (@{$invoice->{SG2}}) {
        my $nad = $_->{NAD}[0];
        if ($nad->{3035} eq 'BY' and $nad->{C082}{3055} eq '91') {
            $buyer_san = $nad->{C082}{3039};
        }
    }

    if (not $buyer_san) {
        $logger->error($log_prefix . "could not find buyer SAN in INVOIC");
        return 0;
    }

    # Find the matching org unit based on SAN via 'aoa' table.
    my $addrs =
        $e->search_actor_org_address({valid => "t", san => $buyer_san});

    if (not $addrs or not @$addrs) {
        $logger->error(
            $log_prefix . "couldn't find OU unit matching buyer SAN in INVOIC:".
            $e->event
        );
        return 0;
    }

    # XXX Should we verify that this matches PO ordering agency later?
    $eg_inv->receiver($addrs->[0]->org_unit);

    try {
        $eg_inv->inv_ident($invoice->{BGM}[0]{1004});
    } catch Error with {
        $logger->error(
            $log_prefix . "no invoice ID # in INVOIC message; " . shift
        );
    }
    return 0 unless $eg_inv->inv_ident;

    my @eg_inv_entries;

    # The invoice message will have once instance of segment group 25
    # per lineitem.
    foreach my $sg25 (@{ $invoice->{SG25} }) {
        # quantity
        my $c186 = $sg25->{QTY}[0]{C186};
        my $quantity = $c186->{6060};
        # $c186->{6411} will probably say 'PCE', but need we check it?

        # identifiers (typically ISBN for us, and we may not need these)
        my @identifiers = ();
        #   from LIN...
        try {
            my $c212 = $sg25->{LIN}[0]{C212};
            push @identifiers, [$c212->{7143}, $c212->{7140}] if
                $c212 and ref $c212 eq 'HASH';
        } catch Error with {
            # move on
        };

        #   from PIA...
        try {
            foreach my $pia (@{ $sg25->{PIA} }) {
                foreach my $h (@{$pia->{C212}}) {
                    push @identifiers, [$h->{7143}, $h->{7140}];
                }
            }
        } catch Error with {
            # move on
        };

        # @identifiers now contains lists of, say,
        # ['IB',   '0786222735'], # ISBN 10
        # ['EN','9780786222735']  # ISBN 13

        # Segment Group 26-47 are all descendants of SG25.

        # Segment Group 26 concerns *lineitem* price (i.e, total for all copies
        # on this lineitem).

        my $lineitem_price = $sg25->{SG26}[0]{MOA}[0]{C516}{5004};

        # Segment Group 28 concerns *unit* (lineitem detail) price.  We may
        # not actually use this.  TBD.
        my $per_unit_price;
        foreach my $sg28 (@{$sg25->{SG28}}) {
            my $c509 = $sg28->{PRI}[0]{C509};
            my ($price_qualifier, $price_qualifier_type);
            ($per_unit_price, $price_qualifier, $price_qualifier_type) = (
                $c509->{5118}, $c509->{5125}, $c509->{5387}
            );

            # price_qualifier=AAA seems to be the price to use.  Otherwise,
            # take what we can get.
            last if $price_qualifier eq 'AAA';
        }

        # Segment Group 29 will have references to LI and PO numbers
        my $acq_identifiers = {};
        foreach my $sg29 (@{$sg25->{SG29}}) {
            foreach my $rff (@{$sg29->{RFF}}) {
                my $c506 = $rff->{C506};
                if ($c506->{1153} eq 'ON') {
                    $acq_identifiers->{po} = $c506->{1154};
                } elsif ($c506->{1153} eq 'LI') {
                    my ($po, $li) = split m./., $c506->{1154};
                    if ($po and $li) {
                        if ($acq_identifiers->{po}) {
                            $logger->warn(
                                $log_prefix .
                                "RFFs within lineitem disagree on PO # ?"
                            ) unless $acq_identifiers->{po} eq $po;
                        }
                        $acq_identifiers->{li} = $li;
                        $acq_identifiers->{po} = $po;
                    } else {
                        $logger->warn(
                            $log_prefix .
                            "RFF 1154 doesn't match expectations (.+/.+) " .
                            "where 1153 is 'LI'"
                        );
                    }
                }
            }
        }

        if ($acq_identifiers->{po}) {
            # First PO number seen in INVOIC sets the purchase_order field for
            # the entry in acq.edi_message (which model may need a rethink).

            $message->purchase_order($acq_identifiers->{po}) unless
                $message->purchase_order;
        } else {
            $logger->warn(
                $log_prefix .
                "SG29 missing or refers to no purchase order that we can tell"
            );
        }
        if (not $acq_identifiers->{li}) {
            $logger->warn(
                $log_prefix .
                "SG29 missing or refers to no lineitem that we can tell"
            );
        }

        my $eg_inv_entry = Fieldmapper::acq::invoice_entry->new;
        $eg_inv_entry->inv_item_count($quantity);

        # XXX Validate by making sure the LI is on-order and belongs to
        # the right provider and ordering agency and all that.
        $eg_inv_entry->lineitem($acq_identifiers->{li});

        # XXX Do we actually need to link to PO directly here?
        $eg_inv_entry->purchase_order($acq_identifiers->{po});

        # This is the total price for all units billed, not per-unit.
        $eg_inv_entry->cost_billed($lineitem_price);

        push @eg_inv_entries, $eg_inv_entry;
    }

    my @eg_inv_items;

    # Find any taxes applied to the whole invoice.
    try {
        if ($invoice->{SG50}) {
            foreach my $sg50 (@{ $invoice->{SG50} }) {
                if ($sg50->{TAX} and $sg50->{MOA}) {
                    my $tax_amount = $sg50->{MOA}[0]{C516}{5004};

                    my $eg_inv_item = Fieldmapper::acq::invoice_item->new;
                    $eg_inv_item->inv_item_type('TAX');
                    $eg_inv_item->cost_billed($tax_amount);
                    # XXX i18n somehow? or maybe omit the note.
                    $eg_inv_item->note('Tax from electronic invoice');

                    push @eg_inv_items, $eg_inv_item;
                }
            }
        }
    } catch Error with {
        # move on
    };

    $e->xact_begin;

    # save changes to acq.edi_message row
    if (not $e->update_acq_edi_message($message)) {
        $logger->error(
            $log_prefix . "couldn't update edi_message " . $message->id
        );
        return 0;
    }

    # create EG invoice
    if (not $e->create_acq_invoice($eg_inv)) {
        $logger->error($log_prefix . "couldn't create invoice: " . $e->event);
        return 0;
    }

    # Now we have a pkey for our EG invoice, so set the invoice field on all
    # our entries according and create those too.
    my $eg_inv_id = $e->data->id;
    foreach (@eg_inv_entries) {
        $_->invoice($eg_inv_id);
        if (not $e->create_acq_invoice_entry($_)) {
            $logger->error(
                $log_prefix . "couldn't create entry against lineitem " .
                $_->lineitem . ": " . $e->event
            );
            return 0;
        }
    }

    # Create any invoice items (taxes)
    foreach (@eg_inv_items) {
        $_->invoice($eg_inv_id);
        if (not $e->create_acq_invoice_item($_)) {
            $logger->error(
                $log_prefix . "couldn't create inv item: " . $e->event
            );
            return 0;
        }
    }

    $e->xact_commit;
    return 1;
}

# returns message object if processing should continue
# returns false/undef value if processing should abort

sub message_object {
    my $class = shift;
    my $body  = shift or return;
    my $key   = shift if @_;
    my $keystring = $key || 'UNSPECIFIED';

    my $msg = Business::EDI::Message->new($body);
    unless ($msg) {
        $logger->error("EDI interchange message: $keystring body failed Business::EDI constructor. Skipping it.");
        return;
    }
    $key = $msg->code if ! $key;  # Now we set the key for reference if it wasn't specified
    my $val_0065 = $msg->xpath_value('UNH/S009/0065') || '';
    unless ($val_0065 eq $key) {
        $logger->error("EDI $key UNH/S009/0065 ('$val_0065') conflicts w/ message type $key.  Aborting");
        return;
    }
    my $val_0051 = $msg->xpath_value('UNH/S009/0051') || '';
    unless ($val_0051 eq 'UN') {
        $logger->warn("EDI $key UNH/S009/0051 designates '$val_0051', not 'UN' as controlling agency.  Attempting to process anyway");
    }
    my $val_0054 = $msg->xpath_value('UNH/S009/0054') || '';
    if ($val_0054) {
        $logger->info("EDI $key UNH/S009/0054 uses Spec revision version '$val_0054'");
        # Possible Spec Version limitation
        # my $yy = $tag_0054 ? substr($val_0054,0,2) : '';
        # unless ($yy eq '00' or $yy > 94 ...) {
        #     $logger->warn("EDI $key UNH/S009/0051 Spec revision version '$val_0054' not supported");
        # }
    } else {
        $logger->warn("EDI $key UNH/S009/0054 does not reference a known Spec revision version");
    }
    return $msg;
}

=head2 ->eg_li($lineitem_object, [$remote, $server_log_string, $editor])

my $line_item = OpenILS::Application::Acq::EDI->eg_li($edi_line, $remote, "test_server_01", $e);

 $remote is a acq.edi_account Fieldmapper object.
 $server_log_string is an arbitrary string use to identify the remote host in potential log messages.

Updates:
 acq.lineitem.estimated_unit_price, 
 acq.lineitem.state (dependent on mapping codes), 
 acq.lineitem.expected_recv_time, 
 acq.lineitem.edit_time (consequently)

=cut

sub eg_li {
    my ($class, $line, $server, $server_log_string, $e) = @_;
    $line or return;
    $e ||= new_editor();

    my $id;
    # my $rff      = $line->part('line_reference/RFF') or $logger->warn("EDI ORDRSP line_detail/RFF missing!");
    my $val_1153 = $line->xpath_value('line_reference/RFF/1153') || '';
    my $val_1154 = $line->xpath_value('line_reference/RFF/1154') || '';
    my $val_1082 = $line->xpath_value('LIN/1082') || '';

    my @po_nums;

    $val_1154 =~ s#^(.*)\/##;   # Many sources send the ID as 'order_ID/LI_ID'
    $1 and push @po_nums, $1;
    $val_1082 =~ s#^(.*)\/##;   # Many sources send the ID as 'order_ID/LI_ID'
    $1 and push @po_nums, $1;

    # TODO: possible check of po_nums
    # now do a lot of checking

    if ($val_1153 eq 'LI') {
        $id = $val_1154 or $logger->warn("EDI ORDRSP RFF/1154 reference to LI empty.  Attempting failover to LIN/1082");
    } else {
        $logger->warn("EDI ORDRSP RFF/1153 unexpected value ('$val_1153', not 'LI').  Attempting failover to LIN/1082");
    }

    # FIXME - the line item ID in LIN/1082 ought to match RFF/1154, but
    # not all materials vendors obey this.  Commenting out check for now
    # as being too strict.
    #if ($id and $val_1082 and $val_1082 ne $id) {
    #    $logger->warn("EDI ORDRSP LIN/1082 Line Item ID mismatch ($id vs. $val_1082): cannot target update");
    #    return;
    #}

    $id ||= $val_1082 || '';
    if ($id eq '') {
        $logger->warn('Cannot identify line item from EDI message');
        return;
    }

    $logger->info("EDI retrieve/update lineitem $id");

    my $li = OpenILS::Application::Acq::Lineitem::retrieve_lineitem_impl($e, $id, {
        flesh_li_details => 1,
    }, 1); # Could send more {options}.  The 1 is for no_auth.

    if (! $li or ref($li) ne 'Fieldmapper::acq::lineitem') {
        $logger->error("EDI failed to retrieve lineitem by id '$id' for server $server_log_string");
        return;
    }
    unless ((! $server) or (! $server->provider)) {     # but here we want $server to be acq.edi_account instead of RemoteAccount
        if ($server->provider != $li->provider) {
            # links go both ways: acq.provider.edi_default and acq.edi_account.provider
            $logger->info("EDI acct provider (" . $server->provider. ") doesn't match lineitem provider("
                            . $li->provider . ").  Checking acq.provider.edi_default...");
            my $provider = $e->retrieve_acq_provider($li->provider);
            if ($provider->edi_default != $server->id) {
                $logger->error(sprintf "EDI provider/acct %s/%s (%s) is blocked from updating lineitem $id belonging to provider/edi_default %s/%s",
                                $server->provider, $server->id, $server->label, $li->provider, $provider->edi_default);
                return;
            }
        }
    }
    
    my @lin_1229 = $line->xpath('LIN/1229') or $logger->warn("EDI LIN/1229 Action Code missing!");
    my $key = $lin_1229[0] or return;

    my $eg_reason = $e->retrieve_acq_cancel_reason(1000 + $key->value);  # DB populated w/ spec keys in 1000's
    $eg_reason or $logger->warn(sprintf "EDI LIN/1229 Action Code '%s' (%s) not recognized in acq.cancel_reason", $key->value, $key->label);
    $eg_reason or return;

    $li->cancel_reason($eg_reason->id);
    unless ($eg_reason->keep_debits) {
        $logger->warn("EDI LIN/1229 Action Code '%s' (%s) has keep_debits=0", $key->value, $key->label);
    }

    my @prices = $line->xpath_value("line_price/PRI/5118");
    $li->estimated_unit_price($prices[0]) if @prices;

    return $li;
}

# caching not needed for now (edi_fetcher is asynchronous)
# sub get_reason {
#     my ($class, $key, $e) = @_;
#     $reasons->{$key} and return $reasons->{$key};
#     $e ||= new_editor();
#     $reasons->{$key} = $e->retrieve_acq_cancel_reason($key);
#     return $reasons->{$key};
# }

1;

__END__

Example JSON data.

Note the pseudo-hash 2-element arrays.  

[
  'SG26',
  [
    [
      'LIN',
      {
        '1229' => '5',
        '1082' => 1,
        'C212' => {
          '7140' => '9780446360272',
          '7143' => 'EN'
        }
      }
    ],
    [
      'IMD',
      {
        '7081' => 'BST',
        '7077' => 'F',
        'C273' => {
          '7008' => [
            'NOT APPLIC WEBSTERS NEW WORLD THESA'
          ]
        }
      }
    ],
    [
      'QTY',
      {
        'C186' => {
          '6063' => '21',
          '6060' => 10
        }
      }
    ],
    [
      'QTY',
      {
        'C186' => {
          '6063' => '12',
          '6060' => 10
        }
      }
    ],
    [
      'QTY',
      {
        'C186' => {
          '6063' => '85',
          '6060' => 0
        }
      }
    ],
    [
      'FTX',
      {
        '4451' => 'LIN',
        'C107' => {
          '4441' => '01',
          '3055' => '28',
          '1131' => '8B'
        }
      }
    ],
    [
      'SG30',
      [
        [
          'PRI',
          {
            'C509' => {
              '5118' => '4.5',
              '5387' => 'SRP',
              '5125' => 'AAB'
            }
          }
        ]
      ]
    ],
    [
      'SG31',
      [
        [
          'RFF',
          {
            'C506' => {
              '1154' => '8/1',
              '1153' => 'LI'
            }
          }
        ]
      ]
    ]
  ]
],

